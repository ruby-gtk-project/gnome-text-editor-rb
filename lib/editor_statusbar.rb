# frozen_string_literal: true

require 'adwaita'

# EditorStatusbar is the monospace strip under the tabs: the selection size,
# the overwrite indicator and the cursor position.
#
# Ported from upstream's src/editor-statusbar.c and
# src/editor-statusbar.ui. Upstream binds the labels to the page and the
# document through a GBindingGroup and a GSignalGroup so that switching tabs
# re-targets the bindings; this port connects to the document when a page is
# bound and disconnects when it is unbound, which is the same lifetime by
# hand. The command-bar and command labels upstream feeds from its Vim
# emulation stay empty here, because the Vim keybindings are not part of this
# port, so they are not shown.
class EditorStatusbar < Gtk::Box
  CSS_CLASS = 'statusbar'
  OVERWRITE_LABEL = 'OVR'

  def initialize
    super(:horizontal, 12)

    add_css_class(CSS_CLASS)
  end

  def build
    tap do
      append(selection_count)
      append(mode)
      append(position)
    end
  end

  # Points the statusbar at a page, or at nothing. Upstream clears every label
  # first, so a tab with no document shows an empty strip rather than the
  # previous tab's numbers.
  def bind_page(page)
    tap do
      unbind

      clear

      page&.then do |bound|
        @page = bound
        @document = bound.document
        @cursor_handler = @document.signal_connect('cursor_moved') { update }
        @overwrite_handler = bound.view.signal_connect('notify::overwrite') { update }
        update
      end
    end
  end

  def unbind
    tap do
      if @cursor_handler
        @document&.signal_handler_disconnect(@cursor_handler)
      end
      if @overwrite_handler
        @page&.view&.signal_handler_disconnect(@overwrite_handler)
      end
      @cursor_handler = nil
      @overwrite_handler = nil
      @document = nil
      @page = nil
    end
  end

  def set_selection_count(count)
    tap do
      if count.zero?
        selection_count.label = ''
      else
        selection_count.label = count.to_s
      end
    end
  end

  def set_position(line, line_offset)
    tap { position.label = "#{line},#{line_offset}" }
  end

  def set_overwrite(overwrite)
    tap do
      if overwrite
        mode.label = OVERWRITE_LABEL
      else
        mode.label = ''
      end
    end
  end

  def selection_count = @selection_count ||= numeric_label(4)

  def position = @position ||= numeric_label(12)

  def mode
    @mode ||= Gtk::Label.new.tap do |label|
      label.width_chars = 3
      label.max_width_chars = 3
      label.valign = :center
    end
  end

  private

    def clear
      set_selection_count(0)
      set_position(0, 0)
      set_overwrite(false)
    end

    def update
      unless @document.loading?
        @document.cursor_line_column.then { |(line, column)| set_position(line, column) }
        set_selection_count(@document.selection_count)
        set_overwrite(@page.view.overwrite?)
      end
    end

    def numeric_label(width)
      Gtk::Label.new.tap do |label|
        label.width_chars = width
        label.max_width_chars = width
        label.valign = :center
        label.xalign = 0
        label.attributes = Pango::AttrList.new.tap do |attributes|
          attributes.insert(Pango::AttrFontFeatures.new('tnum'))
        end
      end
    end
end
