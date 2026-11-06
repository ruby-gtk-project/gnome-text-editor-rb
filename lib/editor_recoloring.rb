# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'

# EditorRecoloring tints the window's own chrome — the headerbar, the
# sidebar, the dialogs — to match whichever style scheme the buffer is
# showing, so a dark scheme like Builder Dark does not sit inside a
# light-grey window frame.
#
# Ported from upstream's src/editor-recoloring.c and
# src/editor-recoloring-private.h: three free functions —
# _editor_source_style_scheme_is_dark, _editor_recoloring_generate_css and
# _editor_source_style_scheme_get_variant — called from the window and the
# theme selector. This port keeps the same shape as three class methods, and
# the same colour maths: upstream blends colours with CSS's own mix()
# function rather than computing RGB by hand (its #if 0'd premix_colors is
# dead code even there), so this port emits the same "mix(a,b,level)" strings
# rather than reimplementing colour blending.
class EditorRecoloring
  SHARED_CSS = <<~CSS
    @define-color card_fg_color @window_fg_color;
    @define-color headerbar_border_color @window_fg_color;
    @define-color popover_fg_color @window_fg_color;
    @define-color dialog_fg_color @window_fg_color;
    @define-color dark_fill_bg_color @headerbar_bg_color;
    @define-color sidebar_backdrop_color @window_bg_color;
    @define-color sidebar_fg_color @window_fg_color;
    @define-color view_fg_color @window_fg_color;
  CSS
  LIGHT_CSS_SUFFIX = "@define-color card_bg_color alpha(white, .8);\n"
  DARK_CSS_SUFFIX = "@define-color card_bg_color alpha(white, .08);\n"

  class << self
    # Upstream's _editor_source_style_scheme_is_dark: the scheme's own
    # "variant" metadata when it has one, an "-dark" id, or the HSP
    # perceived brightness of its "text" background.
    def dark?(scheme)
      case scheme.get_metadata('variant')
      when 'light' then false
      when 'dark' then true
      else
        if scheme.id.end_with?('-dark')
          true
        else
          background(scheme, 'text')&.then { |color| perceived_brightness(color) <= 127.5 } || false
        end
      end
    end

    # Upstream's _editor_recoloring_generate_css: nil for Adwaita, which the
    # window is already coloured for, otherwise a stylesheet of
    # @define-color rules the window's own CssProvider can load.
    def generate_css(scheme)
      unless scheme.name.start_with?('Adwaita')
        new(scheme).css
      end
    end

    # Upstream's _editor_source_style_scheme_get_variant: the scheme to use
    # for a given light/dark variant — its own "light-variant"/"dark-variant"
    # metadata, a sibling found by swapping the id's "-light"/"-dark" suffix,
    # or the scheme itself when neither turns up anything.
    def variant(scheme, variant_name)
      manager = GtkSource::StyleSchemeManager.default
      mapped = scheme.get_metadata("#{variant_name}-variant")

      (mapped && manager.get_scheme(mapped)) ||
        manager.get_scheme(sibling_id(scheme.id, variant_name)) ||
        manager.get_scheme(scheme.id.sub(/-(?:light|dark)\z/, '')) ||
        scheme
    end

    def background(scheme, style_name)
      style = scheme.get_style(style_name)
      if style&.background_set?
        Gdk::RGBA.parse(style.background)
      end
    end

    def foreground(scheme, style_name)
      style = scheme.get_style(style_name)
      if style&.foreground_set?
        Gdk::RGBA.parse(style.foreground)
      end
    end

    # http://alienryderflex.com/hsp.html
    def perceived_brightness(color)
      Math.sqrt(
        (0.299 * (color.red * 255)**2) +
        (0.587 * (color.green * 255)**2) +
        (0.114 * (color.blue * 255)**2),
      )
    end

    def sibling_id(id, variant_name) = "#{id.sub(/-(?:light|dark)\z/, '')}-#{variant_name}"
  end

  def initialize(scheme)
    @scheme = scheme
    @dark = self.class.dark?(scheme)
    @text_bg = self.class.background(scheme, 'text')
    @text_fg = self.class.foreground(scheme, 'text')
    if @dark
      @alt = 'white'
    else
      @alt = 'black'
    end
    @has_bg = !@text_bg.nil?
    @has_fg = !@text_fg.nil?
  end

  # Builds the same stylesheet upstream's GString walk does, rule by rule, in
  # the same order.
  def css
    (+SHARED_CSS).tap do |str|
      str << "/* #{@scheme.name} */\n"
      str << window_bg_rule
      str << window_fg_rule
      str << sidebar_fg_rule
      str << sidebar_bg_rule
      str << headerbar_bg_rule
      str << headerbar_fg_rule
      str << popover_bg_rule
      str << dialog_bg_rule
      str << view_bg_rule
      str << color_rule('view_fg_color', @text_fg)
      str << accent_rules
      str << (@dark ? DARK_CSS_SUFFIX : LIGHT_CSS_SUFFIX)
    end
  end

  private

    def metadata(key) = @scheme.get_metadata(key)&.then { |value| Gdk::RGBA.parse(value) }

    def color_rule(name, color) = color ? "@define-color #{name} #{opaque(color)};\n" : ''

    # Upstream's define_color_mixed: gdk_rgba_to_string on each colour as
    # handed in, with no forced opacity — CSS's mix() blends the alpha too.
    def mix_rule(name, a, b, level) = "@define-color #{name} mix(#{color_str(a)},#{color_str(b)},#{format('%.2f', level)});\n"

    def color_str(color) = color.is_a?(String) ? color : color.to_s

    def opaque(color)
      color.dup.tap { |copy| copy.alpha = 1.0 }
    end

    def window_bg_rule
      metadata('window_bg_color')&.then { |color| color_rule('window_bg_color', color) } ||
        if @has_bg && @has_fg && @dark
          color_rule('window_bg_color', @text_bg)
        elsif @has_bg && @has_fg
          mix_rule(
            'window_bg_color',
            @text_bg,
            @text_fg,
            0.03,
          )
        elsif @dark
          mix_rule(
            'window_bg_color',
            @text_bg,
            'white',
            0.025,
          )
        else
          mix_rule(
            'window_bg_color',
            @text_bg,
            'white',
            0.1,
          )
        end
    end

    def window_fg_rule
      metadata('window_fg_color')&.then { |color| color_rule('window_fg_color', color) } ||
        if @has_bg && @has_fg
          color_rule('window_fg_color', @text_fg)
        elsif @dark
          mix_rule(
            'window_fg_color',
            @text_bg,
            @alt,
            0.05,
          )
        else
          mix_rule(
            'window_fg_color',
            @text_bg,
            @alt,
            0.025,
          )
        end
    end

    def sidebar_fg_rule
      color = metadata('sidebar_fg_color') || self.class.foreground(@scheme, 'line-numbers') || @text_fg
      color_rule('sidebar_fg_color', color)
    end

    def sidebar_bg_rule
      color = metadata('sidebar_bg_color') || self.class.background(@scheme, 'line-numbers') || @text_bg
      color_rule('sidebar_bg_color', color)
    end

    def headerbar_bg_rule
      metadata('headerbar_bg_color')&.then { |color| color_rule('headerbar_bg_color', color) } ||
        mix_rule(
          'headerbar_bg_color',
          @text_bg,
          'white',
          @dark ? 0.07 : 0.25,
        )
    end

    def headerbar_fg_rule
      metadata('headerbar_fg_color')&.then { |color| color_rule('headerbar_fg_color', color) } ||
        if @has_bg && @has_fg
          color_rule('headerbar_fg_color', @text_fg)
        elsif @dark
          mix_rule(
            'headerbar_fg_color',
            @text_bg,
            @alt,
            0.05,
          )
        else
          mix_rule(
            'headerbar_fg_color',
            @text_bg,
            @alt,
            0.025,
          )
        end
    end

    def popover_bg_rule
      metadata('popover_bg_color')&.then { |color| color_rule('popover_bg_color', color) } ||
        mix_rule(
          'popover_bg_color',
          @text_bg,
          'white',
          @dark ? 0.07 : 0.25,
        )
    end

    def dialog_bg_rule
      if @dark
        mix_rule(
          'dialog_bg_color',
          @text_bg,
          'white',
          0.07,
        )
      else
        color_rule('dialog_bg_color', @text_bg)
      end
    end

    def view_bg_rule
      if @dark
        mix_rule(
          'view_bg_color',
          @text_bg,
          'black',
          0.1,
        )
      else
        mix_rule(
          'view_bg_color',
          @text_bg,
          'white',
          0.3,
        )
      end
    end

    def accent_rules
      background = metadata('accent_bg_color') || self.class.background(@scheme, 'selection')
      foreground = metadata('accent_fg_color') || self.class.foreground(@scheme, 'selection')
      accent = metadata('accent_color')

      "".dup.tap do |str|
        str << color_rule('accent_bg_color', background)
        str << color_rule('accent_fg_color', foreground)
        if accent
          str << color_rule('accent_color', accent)
        elsif background
          str << mix_rule(
            'accent_color',
            opaque(background),
            @alt,
            0.1,
          )
        end
      end
    end
end
