# frozen_string_literal: true

require 'adwaita'

# EditorDocumentStatistics counts the lines, words, characters and whitespace
# in a document for the properties panel.
#
# Ported from upstream's src/editor-document-statistics.c. Upstream copies the
# buffer's text into a worker thread, walks it with pango_get_log_attrs() and
# applies the result back on the main loop with a GCancellable guarding stale
# runs. The counts here come from Ruby's Unicode-aware regexps on the main
# loop: the work is a single pass over a string already in memory, and keeping
# it on the main loop means no cancellation bookkeeping. The 1 second coalescing
# delay upstream uses between keystrokes is kept, because that is what stops
# the recount from running on every character.
class EditorDocumentStatistics
  QUEUED_RELOAD_DELAY = 1000

  # Pango's is_white covers Unicode whitespace; \p{Space} is the same set.
  WHITESPACE = /\p{Space}/
  # Pango's is_word_start, as a pattern: a word character that does not follow
  # one.
  WORD = /\p{Word}+/

  def initialize(document, &on_changed)
    @document = document
    @on_changed = on_changed
    @n_chars = 0
    @n_lines = 0
    @n_printable = 0
    @n_spaces = 0
    @n_words = 0
    @loaded = false
  end

  attr_reader :document, :n_chars, :n_lines, :n_printable, :n_spaces, :n_words

  # False until the first count has run, so the owner can memoize the object
  # before asking for the numbers — a recount tells its listener, and a
  # listener that asks for the statistics again must not create a second
  # object.
  def loaded? = @loaded

  # Recounts now, and tells the listener.
  def reload
    tap do
      cancel_queued

      @document.then do |document|
        count(document.text).then do
          @on_changed&.call(self)
        end
      end
    end
  end

  # Recounts after the coalescing delay; repeated calls inside the window are
  # folded into the one pending recount, exactly as upstream does.
  def queue_reload
    tap do
      @queued_reload ||= GLib::Timeout.add(QUEUED_RELOAD_DELAY) do
        @queued_reload = nil
        reload
        GLib::Source::REMOVE
      end
    end
  end

  def cancel_queued
    tap do
      if @queued_reload
        GLib::Source.remove(@queued_reload)
      end
      @queued_reload = nil
    end
  end

  private

    def count(text)
      @n_chars = text.length
      if text.empty?
        @n_lines = 0
      else
        @n_lines = text.count("\n") + (text.end_with?("\n") ? 0 : 1)
      end
      @n_spaces = text.scan(WHITESPACE).length
      @n_words = text.scan(WORD).length
      @n_printable = @n_chars - @n_spaces
      @loaded = true
      self
    end
end
