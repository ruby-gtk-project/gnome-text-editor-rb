# frozen_string_literal: true

require 'strscan'
require 'adwaita'
require_relative 'editor_page_settings_provider'

# EditorModelineSettingsProvider reads the settings a file carries inside
# itself: a vi(m), Emacs or Kate modeline in its first or last lines.
#
# Ported from upstream's src/modelines/editor-modeline-settings-provider.c and
# src/modelines/modeline-parser.c, which upstream took from gedit. The three
# modeline dialects, the keys each one understands, the lines each one is
# allowed on and the one-second coalescing of re-reads while the user types
# are all upstream's. The language names a modeline uses are translated
# through data/language-mappings, upstream's own table, which it loads from the
# resource bundle and this port reads from the file beside lib/.
class EditorModelineSettingsProvider < EditorPageSettingsProvider
  MAPPINGS_BASENAME = 'language-mappings'

  # Upstream coalesces re-reads one second out, because the document's
  # "changed" fires on every keystroke.
  RELOAD_DELAY = 1

  # How many lines at each end of the file each dialect is read from.
  VIM_WINDOW = 3
  EMACS_WINDOW = 2
  KATE_WINDOW = 10

  # The lines upstream looks at either end before it stops reading.
  SCAN_WINDOW = 10

  def initialize
    super()

    @options = {}
    @reload_source = nil
  end

  def document=(document)
    unless document.equal?(@document)
      super
      document&.signal_connect('changed') { queue_reload }
      cancel_reload
      reload
    end
  end

  def tab_width = @options[:tab_width]

  # Upstream only takes an indent width a modeline asks for when it is a
  # plausible one.
  def indent_width
    @options[:indent_width].then do |width|
      if width && width >= 1 && width <= 32
        width
      end
    end
  end

  def wrap_text = @options[:wrap_text]

  def right_margin_position = @options[:right_margin_position]

  def show_right_margin = @options[:show_right_margin]

  def insert_spaces_instead_of_tabs = @options[:insert_spaces]

  # Re-reads the document's modelines. Upstream also pushes the language a
  # modeline names onto the buffer, which this port does through the
  # document's own language id.
  def reload
    tap do
      @reload_source = nil

      @document.then do |document|
        if document
          @options = self.class.parse(document.text)
          apply_language
          emit_changed
        end
      end
    end
  end

  # The options a text's modelines ask for, as a hash of only the settings
  # they actually named.
  def self.parse(text)
    text.to_s.lines.map(&:chomp).then do |lines|
      {}.tap do |options|
        scanned(lines).each do |index|
          parse_line(
            lines[index],
            index + 1,
            lines.length,
            options,
          )
        end
      end
    end
  end

  # The line indexes upstream reads: the first ten and the last ten.
  def self.scanned(lines)
    lines.length.then do |count|
      (0...[count, SCAN_WINDOW].min).to_a.union(([count - SCAN_WINDOW, SCAN_WINDOW].max...count).to_a)
    end
  end

  # One line, scanned for the start of each dialect's modeline. A modeline
  # only starts at the beginning of the line or after a space, which is what
  # upstream's look-behind checks.
  def self.parse_line(line, line_number, line_count, options)
    StringScanner.new(line.to_s).tap do |scanner|
      until scanner.eos?
        if scanner.pos.positive? && !line[scanner.pos - 1].to_s.match?(/\s/)
          scanner.pos += 1
        else
          dialect(
            scanner,
            line_number,
            line_count,
            options,
          )
        end
      end
    end
  end

  def self.dialect(scanner, line_number, line_count, options)
    if within?(line_number, line_count, VIM_WINDOW) && scanner.scan(/(?:vim|vi|ex):/)
      parse_vim(scanner, options)
    elsif line_number <= EMACS_WINDOW && scanner.scan(/-\*-/)
      parse_emacs(scanner, options)
    elsif within?(line_number, line_count, KATE_WINDOW) && scanner.scan(/kate:/)
      parse_kate(scanner, options)
    else
      scanner.pos += 1
    end
  end

  # Upstream allows a dialect's modeline on the first or last few lines only.
  def self.within?(line_number, line_count, window)
    line_number <= window || line_number > line_count - window
  end

  # "[text] {vi:|vim:|ex:} [set] {options}" — the options are separated by
  # colons or spaces, "no" negates a flag, and a "set" form ends at the next
  # colon.
  def self.parse_vim(scanner, options)
    in_set = false

    until scanner.eos? || (in_set && scanner.peek(1) == ':')
      scanner.skip(/[:\s]*/)

      if scanner.eos?
        break
      end

      if scanner.scan(/se(?:t)?\s+/)
        in_set = true
      end

      negated = !scanner.scan(/no/).nil?
      key = scanner.scan(/[^:=\s]*/).to_s
      value = ''

      if scanner.scan(/=/)
        value = scanner.scan(/[^:\s]*/).to_s
      end

      apply_vim(
        key,
        value,
        negated,
        options,
      )
    end
  end

  def self.apply_vim(key, value, negated, options)
    case key
    when 'ft', 'filetype' then options[:language_id] = language_id(value, 'vim')
    when 'et', 'expandtab' then options[:insert_spaces] = !negated
    when 'ts', 'tabstop' then positive(value).then { |width| set(options, :tab_width, width) }
    when 'sw', 'shiftwidth' then positive(value).then { |width| set(options, :indent_width, width) }
    when 'wrap' then options[:wrap_text] = !negated
    when 'textwidth', 'tw' then positive(value).then { |columns| set_right_margin(options, columns) }
    end
  end

  # "-*- key1: value1; key2: value2 -*-", on the first line or the second one
  # when the first is a shebang.
  def self.parse_emacs(scanner, options)
    until scanner.eos?
      scanner.skip(/[;\s]*/)

      if scanner.eos? || scanner.peek(3) == '-*-'
        break
      end

      key = scanner.scan(/[^:;\s]*/).to_s
      scanner.skip(/\s*/)

      if scanner.eos?
        break
      end

      if scanner.scan(/:/)
        scanner.skip(/\s*/)
        apply_emacs(key, scanner.scan(/[^;\s]*/).to_s, options)
      end
    end

    unless scanner.eos?
      scanner.pos += 2
    end
  end

  def self.apply_emacs(key, value, options)
    case key.downcase
    when 'mode' then options[:language_id] = language_id(value, 'emacs')
    when 'tab-width' then positive(value).then { |width| set(options, :tab_width, width) }
    when 'indent-offset', 'c-basic-offset', 'js-indent-level'
      positive(value).then { |width| set(options, :indent_width, width) }
    when 'indent-tabs-mode' then options[:insert_spaces] = value == 'nil'
    when 'autowrap' then options[:wrap_text] = value != 'nil'
    end
  end

  # "kate: key1 value1; key2 value2;", on the first or last ten lines.
  def self.parse_kate(scanner, options)
    until scanner.eos?
      scanner.skip(/[;\s]*/)

      if scanner.eos?
        break
      end

      key = scanner.scan(/[^;\s]*/).to_s
      scanner.skip(/\s*/)

      if scanner.eos?
        break
      end

      unless scanner.peek(1) == ';'
        apply_kate(key, scanner.scan(/[^;\s]*/).to_s, options)
      end
    end
  end

  def self.apply_kate(key, value, options)
    case key
    when 'hl', 'syntax' then options[:language_id] = language_id(value, 'kate')
    when 'tab-width' then positive(value).then { |width| set(options, :tab_width, width) }
    when 'indent-width' then positive(value).then { |width| set(options, :indent_width, width) }
    when 'space-indent' then options[:insert_spaces] = enabled?(value)
    when 'word-wrap' then options[:wrap_text] = enabled?(value)
    when 'word-wrap-column' then positive(value).then { |columns| set_right_margin(options, columns) }
    end
  end

  # Kate writes its flags as on/true/1.
  def self.enabled?(value) = %w[on true 1].include?(value)

  # Upstream ignores a width that does not parse as a positive number, which
  # is what atoi gives it for anything else.
  def self.positive(value)
    value.to_i.then do |number|
      if number.positive?
        number
      end
    end
  end

  def self.set(options, key, value)
    unless value.nil?
      options[key] = value
    end
  end

  # A text width turns the right margin on as well as placing it.
  def self.set_right_margin(options, columns)
    unless columns.nil?
      options[:right_margin_position] = columns
      options[:show_right_margin] = true
    end
  end

  # The language id a dialect's name maps to; an unmapped name is assumed to
  # be the id already, which is upstream's fallback.
  def self.language_id(name, dialect)
    name.downcase.then do |downcased|
      mappings.fetch(dialect, {}).fetch(downcased, downcased)
    end
  end

  # data/language-mappings, upstream's key file, read once.
  def self.mappings
    @mappings ||= read_mappings(
      File.expand_path(
        File.join(
          __dir__,
          '..',
          'data',
          MAPPINGS_BASENAME,
        ),
      ),
    )
  end

  def self.read_mappings(path)
    {}.tap do |groups|
      current = nil

      if File.file?(path)
        File.readlines(path, chomp: true).each do |line|
          case line.strip
          when /\A\[(.+)\]\z/ then current = (groups[Regexp.last_match(1)] = {})
          when /\A([^=]+)=(.*)\z/ then current&.[]=(Regexp.last_match(1).strip, Regexp.last_match(2).strip)
          end
        end
      end
    end
  end

  private

    # Upstream sets the buffer's language from the modeline, with "text"
    # meaning no language at all.
    def apply_language
      if @options.key?(:language_id)
        @options[:language_id].then do |id|
          if id == 'text'
            @document.language_id = nil
          else
            @document.language_id = id
          end
        end
      end
    end

    def queue_reload
      tap do
        cancel_reload
        @reload_source = GLib::Timeout.add_seconds(RELOAD_DELAY) do
          reload
          GLib::Source::REMOVE
        end
      end
    end

    def cancel_reload
      tap do
        @reload_source.then do |source|
          if source
            GLib::Source.remove(source)
            @reload_source = nil
          end
        end
      end
    end
end
