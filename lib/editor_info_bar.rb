# frozen_string_literal: true

require 'adwaita'

# EditorInfoBar is the strip above the text that reports what went wrong, or
# what was restored.
#
# Ported from upstream's src/editor-info-bar.c and src/editor-info-bar.ui,
# which stack three GtkInfoBars in a box and reveal whichever applies: the
# access error with Retry and "Open As Administrator", the "Document Restored"
# notice with Discard and Save, and the encoding warning with "Change
# Encoding…". GtkInfoBar is deprecated in GTK 4, so each of the three is built
# here from a revealer around a box carrying the same title, subtitle and
# buttons, with libadwaita's warning and error style classes doing what
# GtkInfoBar's message-type did.
class EditorInfoBar < Gtk::Box
  def initialize
    super(:vertical, 0)
  end

  def build
    tap do
      append(access_revealer)
      append(discard_revealer)
      append(encoding_revealer)

      access_retry_button.signal_connect('clicked') { @on_retry&.call }
      access_admin_button.signal_connect('clicked') { @on_use_admin&.call }
      discard_button.signal_connect('clicked') { @on_discard&.call }
      save_button.signal_connect('clicked') { @on_save&.call }
    end
  end

  def on_retry(&block)
    tap { @on_retry = block }
  end

  def on_use_admin(&block)
    tap { @on_use_admin = block }
  end

  def on_discard(&block)
    tap { @on_discard = block }
  end

  def on_save(&block)
    tap { @on_save = block }
  end

  # Shows the whole state of a document in one call: this is what the page
  # calls whenever the document's error, restored or encoding state changes.
  def update(document)
    tap do
      show_access_error(document)
      discard_revealer.reveal_child = document.was_restored?
      encoding_revealer.reveal_child = document.fallback_used?
    end
  end

  def show_access_error(document)
    tap do
      document.had_error?.then do |had_error|
        access_title.label = error_title(document)
        access_subtitle.label = document.error_message.to_s
        access_admin_button.visible = document.suggest_admin?
        access_revealer.reveal_child = had_error
      end
    end
  end

  def access_revealer = @access_revealer ||= revealer(access_bar)
  def discard_revealer = @discard_revealer ||= revealer(discard_bar)
  def encoding_revealer = @encoding_revealer ||= revealer(encoding_bar)

  def access_bar
    @access_bar ||= bar('error').tap do |box|
      box.append(message_box(access_title, access_subtitle))
      box.append(access_retry_button)
      box.append(access_admin_button)
    end
  end

  def discard_bar
    @discard_bar ||= bar('warning').tap do |box|
      box.append(message_box(discard_title, discard_subtitle))
      box.append(discard_button)
      box.append(save_button)
    end
  end

  def encoding_bar
    @encoding_bar ||= bar('warning').tap do |box|
      box.append(message_box(encoding_title, encoding_subtitle))
      box.append(change_encoding_button)
    end
  end

  def access_title = @access_title ||= title_label('')
  def access_subtitle = @access_subtitle ||= subtitle_label('')
  def discard_title = @discard_title ||= title_label('Document Restored')
  def discard_subtitle = @discard_subtitle ||= subtitle_label('Unsaved document has been restored.')
  def encoding_title = @encoding_title ||= title_label('Invalid Characters Detected')

  def encoding_subtitle
    @encoding_subtitle ||= subtitle_label('There was an encoding conversion error so a fallback character was used.')
  end

  def access_retry_button = @access_retry_button ||= action_button('_Retry')

  def access_admin_button
    @access_admin_button ||= action_button('Open As _Administrator').tap { |button| button.visible = false }
  end

  def discard_button = @discard_button ||= action_button('_Discard…')
  def save_button = @save_button ||= action_button('_Save…')

  def change_encoding_button
    @change_encoding_button ||= action_button('Change _Encoding…').tap do |button|
      button.action_name = 'page.change-encoding'
    end
  end

  private

    # Upstream's title is "Unable to Open" for a load failure; a save failure
    # reports itself the same way, so the heading follows the document.
    def error_title(document)
      document.file ? "Unable to Access “#{File.basename(document.file.parse_name)}”" : 'Unable to Access Document'
    end

    def revealer(child)
      Gtk::Revealer.new.tap do |widget|
        widget.reveal_child = false
        widget.child = child
      end
    end

    def bar(style)
      Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_top = 6
        box.margin_bottom = 6
        box.margin_start = 12
        box.margin_end = 12
        box.add_css_class(style)
        box.add_css_class('toolbar')
      end
    end

    def message_box(title, subtitle)
      Gtk::Box.new(:vertical, 0).tap do |box|
        box.hexpand = true
        box.append(title)
        box.append(subtitle)
      end
    end

    def title_label(text)
      Gtk::Label.new(text).tap do |label|
        label.halign = :start
        label.wrap = true
        label.wrap_mode = :word_char
        label.add_css_class('heading')
      end
    end

    def subtitle_label(text)
      Gtk::Label.new(text).tap do |label|
        label.halign = :start
        label.wrap = true
        label.wrap_mode = :word_char
      end
    end

    def action_button(label)
      Gtk::Button.new.tap do |button|
        button.label = label
        button.use_underline = true
        button.valign = :center
      end
    end
end
