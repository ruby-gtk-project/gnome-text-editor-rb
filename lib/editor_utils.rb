# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_animation'

# EditorUtils holds the small conversions and widget tricks the rest of the
# editor shares.
#
# Ported from upstream's src/editor-utils.c. The GBinding transform functions
# upstream keeps here (_editor_gboolean_to_wrap_mode and friends) are plain
# conversions in this port, since the Ruby bindings connect notify signals
# rather than installing GBinding transforms; the GtkSourceView-specific ones
# (style scheme lookup, background pattern) have no counterpart because the
# port draws into a GtkTextView.
module EditorUtils
  FADE_DELAY = 1000

  class << self
    # Renders a Pango font description as the CSS declarations GTK understands,
    # so a font chosen in the preferences can be applied through a CssProvider.
    def font_description_to_css(font_desc)
      [].tap do |declarations|
        family = font_desc.family
        if family
          declarations << %(font-family:"#{family}";)
        end

        declarations << "font-variant:#{css_variant(font_desc.variant)};"
        declarations << "font-weight:#{css_weight(font_desc.weight)};"
        declarations << "font-stretch:#{css_stretch(font_desc.stretch)};"

        (font_desc.size / Pango::SCALE).then do |size|
          if size.positive?
            declarations << "font-size:#{size}pt;"
          end
        end
      end.join
    end

    # "Just now", "Yesterday", a weekday, a month name, or a count of years —
    # the same ladder upstream's _editor_date_time_format walks.
    def date_time_format(time)
      (Time.now.utc - time.utc).to_i.then do |diff|
        case diff
        when ...0 then ''
        when ...(60 * 45) then 'Just now'
        when ...(60 * 90) then 'An hour ago'
        when ...(60 * 60 * 24 * 2) then 'Yesterday'
        when ...(60 * 60 * 24 * 7) then time.strftime('%A')
        when ...(60 * 60 * 24 * 365) then time.strftime('%B')
        when ...(60 * 60 * 24 * 365 * 1.5) then 'About a year ago'
        else years_ago(diff / (60 * 60 * 24 * 365))
        end
      end
    end

    # Fades a widget out and then hides it, leaving the opacity restored so the
    # next show is not invisible.
    def widget_hide_with_fade(widget, delay = FADE_DELAY)
      fade_animations[widget.object_id]&.stop

      if widget.visible?
        EditorAnimation.new(widget, duration: delay) do
          fade_animations.delete(widget.object_id)
          widget.visible = false
          widget.opacity = 1.0
        end.to(:opacity, 0.0).start.then { |animation| fade_animations[widget.object_id] = animation }
      end
    end

    # Keeps a revealer out of the size-request machinery until it is actually
    # revealing something, which is what upstream's _editor_revealer_auto_hide
    # buys: a collapsed revealer stops claiming height.
    def revealer_auto_hide(revealer)
      revealer.tap do |widget|
        widget.signal_connect('notify::reveal-child') { queue_autohide(widget) }
        widget.signal_connect('notify::child-revealed') { queue_autohide(widget) }
        queue_autohide(widget)
      end
    end

    # GTK's wrap mode for the "wrap-text" setting.
    def wrap_mode(wrap_text) = wrap_text ? :word_char : :none

    # The scroll policy upstream picks when text wrapping removes the need for
    # a horizontal scrollbar.
    def scroll_policy(wrap_text) = wrap_text ? :external : :automatic

    # Builds a GtkShortcut from an accelerator string and an action name.
    # Upstream writes these as gtk_widget_class_add_binding_action calls and as
    # <property name="trigger"> in its templates, both of which parse the same
    # "<Control><Shift>s" syntax; the Ruby bindings expose no accelerator
    # parser, so the syntax is parsed here.
    def shortcut(accelerator, action_name, argument = nil)
      Gtk::Shortcut.new(shortcut_trigger(accelerator), Gtk::NamedAction.new(action_name)).tap do |item|
        unless argument.nil?
          item.arguments = argument
        end
      end
    end

    def shortcut_trigger(accelerator)
      parse_accelerator(accelerator).then do |(keyval, modifiers)|
        Gtk::KeyvalTrigger.new(keyval, modifiers)
      end
    end

    # The modifier names GTK's own parser accepts, lower-cased.
    MODIFIERS = {
      'control' => Gdk::ModifierType::CONTROL_MASK,
      'ctrl'    => Gdk::ModifierType::CONTROL_MASK,
      'primary' => Gdk::ModifierType::CONTROL_MASK,
      'shift'   => Gdk::ModifierType::SHIFT_MASK,
      'alt'     => Gdk::ModifierType::ALT_MASK,
      'meta'    => Gdk::ModifierType::META_MASK,
      'super'   => Gdk::ModifierType::SUPER_MASK,
    }.freeze

    def parse_accelerator(accelerator)
      accelerator.scan(/<([^>]+)>/).flatten.then do |names|
        [Gdk::Keyval.from_name(accelerator.sub(/\A(<[^>]+>)*/, '')),
         names.map { |name| MODIFIERS.fetch(name.downcase, Gdk::ModifierType::NO_MODIFIER_MASK) }
              .reduce(Gdk::ModifierType::NO_MODIFIER_MASK) { |all, mask| all | mask }
]
      end
    end

    private

      def fade_animations = @fade_animations ||= {}

      def years_ago(years)
        [2, years].max.then do |count|
          count == 1 ? 'About 1 year ago' : "About #{count} years ago"
        end
      end

      def queue_autohide(revealer)
        if revealer.parent
          GLib::Idle.add(GLib::PRIORITY_HIGH) do
            autohide(revealer)
            GLib::Source::REMOVE
          end
        end

        if (revealer.reveal_child? || revealer.child_revealed?) && !revealer.visible?
          revealer.visible = true
        end
      end

      def autohide(revealer)
        if revealer.parent && !revealer.reveal_child? && !revealer.child_revealed?
          revealer.visible = false
        end
      end

      def css_variant(variant)
        {
          Pango::Variant::NORMAL          => 'normal',
          Pango::Variant::SMALL_CAPS      => 'small-caps',
          Pango::Variant::ALL_SMALL_CAPS  => 'all-small-caps',
          Pango::Variant::PETITE_CAPS     => 'petite-caps',
          Pango::Variant::ALL_PETITE_CAPS => 'all-petite-caps',
          Pango::Variant::UNICASE         => 'unicase',
          Pango::Variant::TITLE_CAPS      => 'titling-caps',
        }.fetch(variant, 'normal')
      end

      # Upstream spells bold and normal as keywords and rounds everything else
      # to the nearest hundred, because numeric font-weight misbehaved in GTK.
      def css_weight(weight)
        case weight
        when Pango::Weight::NORMAL, Pango::Weight::SEMILIGHT then 'normal'
        when Pango::Weight::BOLD then 'bold'
        else ((weight.to_i / 100.0).round * 100).to_s
        end
      end

      def css_stretch(stretch)
        {
          Pango::Stretch::ULTRA_CONDENSED => 'ultra-condensed',
          Pango::Stretch::EXTRA_CONDENSED => 'extra-condensed',
          Pango::Stretch::CONDENSED       => 'condensed',
          Pango::Stretch::SEMI_CONDENSED  => 'semi-condensed',
          Pango::Stretch::NORMAL          => 'normal',
          Pango::Stretch::SEMI_EXPANDED   => 'semi-expanded',
          Pango::Stretch::EXPANDED        => 'expanded',
          Pango::Stretch::EXTRA_EXPANDED  => 'extra-expanded',
          Pango::Stretch::ULTRA_EXPANDED  => 'ultra-expanded',
        }.fetch(stretch, 'normal')
      end
  end
end
