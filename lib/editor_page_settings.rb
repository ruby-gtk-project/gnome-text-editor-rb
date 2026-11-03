# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_modeline_settings_provider'
require_relative 'editor_page_defaults'
require_relative 'editor_page_editorconfig'
require_relative 'editor_page_gsettings'
require_relative 'editor_page_settings_provider'

# EditorPageSettings is the settings one open document is edited under: the
# user's preferences, overruled by the per-language house style, overruled by
# an .editorconfig, overruled by a modeline in the file itself, overruled by
# whatever the user changed by hand for this document alone.
#
# Ported from upstream's src/editor-page-settings.c. Upstream keeps the stack
# in a GPtrArray of providers, asks each one in turn for every setting and
# notifies a GObject property when the answer changes; this port keeps the
# same stack in the same order and tells its listeners which settings moved,
# which is what the page needs to know. Upstream's per-property "user
# override" bits, which stop the providers from being consulted at all, are
# #override here.
#
# The providers are rebuilt whenever "discover-settings" changes, exactly as
# upstream rebuilds them: with discovery off, only the GSettings provider is
# left.
class EditorPageSettings
  KEYS = EditorPageSettingsProvider::KEYS

  # What a setting is before any provider has spoken — upstream's values for
  # an unanswered getter.
  DEFAULTS = {
    custom_font:                   nil,
    style_scheme:                  nil,
    style_variant:                 nil,
    insert_spaces_instead_of_tabs: false,
    right_margin_position:         80,
    show_line_numbers:             false,
    show_right_margin:             false,
    use_system_font:               false,
    wrap_text:                     false,
    tab_width:                     8,
    indent_width:                  -1,
    show_map:                      false,
    show_grid:                     false,
    highlight_current_line:        false,
    highlight_matching_brackets:   false,
    auto_indent:                   false,
    implicit_trailing_newline:     false,
  }.freeze

  def initialize(document, settings:)
    @document = document
    @settings = settings
    @values = DEFAULTS.dup
    @overrides = {}
    @providers = []
    @listeners = []
  end

  attr_reader :document

  # Upstream's constructed: build the stack, and rebuild it whenever the user
  # turns settings discovery on or off.
  def build
    tap do
      rebuild_providers
      @settings.on_changed('discover-settings') { rebuild_providers }
    end
  end

  # Calls the block with the list of settings that changed.
  def on_changed(&block)
    tap { @listeners << block }
  end

  KEYS.each do |key|
    define_method(key) do
      @overrides.fetch(key) { @values[key] }
    end
  end

  # Upstream exposes the indent style as an enum alongside the boolean.
  def indent_style
    if insert_spaces_instead_of_tabs
      'space'
    else
      'tab'
    end
  end

  # Settings the user chose for this document alone. Upstream sets the
  # matching property, which raises the same "ignore the providers for this
  # one" bit.
  def override(key, value)
    tap do
      unless @overrides[key] == value
        @overrides[key] = value
        notify([key])
      end
    end
  end

  def overridden?(key) = @overrides.key?(key)

  # Asks the stack again for every setting and tells the listeners which ones
  # moved. Upstream's editor_page_settings_update.
  def update
    tap do
      KEYS.select { |key| apply_from_providers(key) }.then do |changed|
        unless changed.empty?
          notify(changed)
        end
      end
    end
  end

  private

    # The providers, nearest-to-the-document first, which is the order
    # upstream adds them in.
    def rebuild_providers
      tap do
        @providers = []

        if @settings.discover_settings?
          @providers << EditorModelineSettingsProvider.new
          @providers << EditorPageEditorconfig.new
          @providers << EditorPageDefaults.new
        end

        @providers << EditorPageGsettings.new(@settings)

        @providers.each do |provider|
          provider.on_changed { update }
          provider.document = @document
        end

        update
      end
    end

    # True when the setting's value moved. A setting the user overrode is left
    # alone, and a provider that answers nil is passed over.
    def apply_from_providers(key)
      if @overrides.key?(key)
        false
      else
        provided(key).then do |value|
          if value.nil? || value == @values[key]
            false
          else
            @values[key] = value
            true
          end
        end
      end
    end

    # The first answer the stack gives for one setting.
    def provided(key)
      @providers.lazy.map { |provider| provider.public_send(key) }.find { |value| !value.nil? }
    end

    def notify(changed)
      tap { @listeners.each { |listener| listener.call(changed) } }
    end
end
