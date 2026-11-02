# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'adwaita'

# EditorSettings is the application's settings: the keys of
# data/schemas/org.rubygtkproject.GnomeTextEditor.gschema.xml.
#
# Upstream reads these with GSettings throughout (src/editor-application.c,
# src/editor-window-actions.c, src/editor-preferences-dialog.c), and so does
# this port whenever the compiled schema is installed — a packaged build
# installs it, and `glib-compile-schemas data/schemas` makes the dev shell see
# it. GLib aborts the process when a schema is missing rather than raising, so
# a checkout without the compiled schema would be unable to start; for that
# case the same keys, defaults and ranges are backed by a JSON file under
# XDG_CONFIG_HOME, behind the same API.
class EditorSettings
  SCHEMA_ID = 'org.rubygtkproject.GnomeTextEditor'
  BASENAME = 'settings.json'

  # key => default. The types follow the schema: booleans, unsigned integers,
  # one signed integer, one double and the strings with choices.
  DEFAULTS = {
    'auto-save-delay'             => 3,
    'style-variant'               => 'follow',
    'indent-style'                => 'tab',
    'auto-indent'                 => true,
    'tab-width'                   => 8,
    'indent-width'                => -1,
    'show-line-numbers'           => false,
    'show-right-margin'           => false,
    'right-margin-position'       => 80,
    'show-map'                    => false,
    'show-grid'                   => false,
    'highlight-current-line'      => false,
    'wrap-text'                   => true,
    'use-system-font'             => true,
    'custom-font'                 => 'Monospace 11',
    'style-scheme'                => 'Adwaita',
    'discover-settings'           => true,
    'spellcheck'                  => true,
    'restore-session'             => true,
    'recolor-window'              => true,
    'keybindings'                 => 'default',
    'last-save-directory'         => '',
    'enable-snippets'             => false,
    'line-height'                 => 1.2,
    'highlight-matching-brackets' => true,
  }.freeze

  def initialize(path: nil)
    if schema_installed?
      @gsettings = Gio::Settings.new(SCHEMA_ID)
    else
      @gsettings = nil
    end
    @path = path || default_path
    unless @gsettings
      @values = DEFAULTS.merge(read_json)
    end
    @listeners = {}
  end

  # True when the values come from GSettings rather than the JSON fallback.
  def gsettings? = !@gsettings.nil?

  def [](key)
    @gsettings ? read_gsettings(key) : @values.fetch(key.to_s, DEFAULTS[key.to_s])
  end

  def []=(key, value)
    if @gsettings
      write_gsettings(key.to_s, value)
    else
      @values[key.to_s] = value
      write_json
    end

    notify(key.to_s, value)
    value
  end

  # Calls the block whenever a key changes, however it is stored.
  def on_changed(key, &block)
    tap do
      (@listeners[key.to_s] ||= []) << block
      @gsettings&.signal_connect("changed::#{key}") { block.call(self[key]) }
    end
  end

  # A stateful GAction per key, which is what the window's "settings" action
  # group is made of; GSettings builds these itself, and the fallback builds
  # the equivalent.
  def create_action(key)
    @gsettings ? @gsettings.create_action(key.to_s) : fallback_action(key.to_s)
  end

  DEFAULTS.each_key do |key|
    method_name = key.tr('-', '_')
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
    if DEFAULTS[key].is_a?(TrueClass) ||
                                                               DEFAULTS[key].is_a?(FalseClass)
      define_method(:"#{method_name}?") { self[key] == true }
    end
  end

  private

    def schema_installed?
      !Gio::SettingsSchemaSource.default.lookup(SCHEMA_ID, true).nil?
    end

    def default_path = File.join(GLib.user_config_dir, SCHEMA_ID, BASENAME)

    def read_json
      File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
    rescue StandardError
      {}
    end

    def write_json
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    rescue StandardError
      nil
    end

    # The GVariant type to use is implied by the default's Ruby class, which is
    # how the two stores stay in step.
    def read_gsettings(key)
      case DEFAULTS.fetch(key.to_s)
      when true, false then @gsettings.get_boolean(key.to_s)
      when Float then @gsettings.get_double(key.to_s)
      when Integer then integer_value(key.to_s)
      else @gsettings.get_string(key.to_s)
      end
    end

    def write_gsettings(key, value)
      case DEFAULTS.fetch(key)
      when true, false then @gsettings.set_boolean(key, value)
      when Float then @gsettings.set_double(key, value)
      when Integer then set_integer(key, value)
      else @gsettings.set_string(key, value.to_s)
      end
    end

    # "indent-width" is the one signed key in the schema; the rest are
    # unsigned.
    def integer_value(key)
      key == 'indent-width' ? @gsettings.get_int(key) : @gsettings.get_uint(key)
    end

    def set_integer(key, value)
      key == 'indent-width' ? @gsettings.set_int(key, value.to_i) : @gsettings.set_uint(key, value.to_i)
    end

    def notify(key, value)
      unless @gsettings
        @listeners.fetch(key, []).each { |listener| listener.call(value) }
      end
    end

    # A boolean key becomes a toggle, a string key an enum-style radio — the
    # two shapes GSettings' own create_action produces.
    def fallback_action(key)
      DEFAULTS.fetch(key).then do |default|
        case default
        when true, false then boolean_action(key)
        when String then string_action(key)
        else integer_action(key, default)
        end
      end
    end

    def boolean_action(key)
      Gio::SimpleAction.new(key, nil, GLib::Variant.new(self[key] == true)).tap do |action|
        action.signal_connect('activate') do
          (!action.state.get_boolean).tap do |value|
            action.set_state(GLib::Variant.new(value))
            self[key] = value
          end
        end
      end
    end

    def string_action(key)
      Gio::SimpleAction.new(key, GLib::VariantType.new('s'), GLib::Variant.new(self[key].to_s))
                       .tap do |action|
        action.signal_connect('change-state') do |_action, value|
          action.set_state(value)
          self[key] = value.get_string
        end
      end
    end

    def integer_action(key, default)
      if default.is_a?(Float)
        type = 'd'
      else
        type = 'i'
      end
      Gio::SimpleAction.new(key, GLib::VariantType.new(type), GLib::Variant.new(self[key]))
                       .tap do |action|
        action.signal_connect('change-state') do |_action, value|
          action.set_state(value)

          if default.is_a?(Float)
            self[key] = value.get_double
          else
            self[key] = value.get_int32
          end
        end
      end
    end
end
