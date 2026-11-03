# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_page_settings_provider'

# EditorPageEditorconfig is the .editorconfig provider: the indentation and
# line length a project checked in beside its files, which beat the user's own
# preferences for the files they cover.
#
# Ported from upstream's src/editorconfig/editor-page-editorconfig.c together
# with src/editorconfig/editorconfig-glib.c. Upstream's glib shim hands the
# work to libeditorconfig and then keeps the five keys it cares about —
# tab_width, max_line_length, indent_style, indent_size and
# insert_final_newline; there is no libeditorconfig binding for Ruby, so the
# reading of the files is here, following the .editorconfig specification:
# every directory from the file's own up to one holding "root = true" is read,
# a nearer file beats a farther one, a later section beats an earlier one, and
# "indent_size = tab" takes the tab width.
#
# Upstream re-reads on the document's notify::file. A document in this port
# only changes file when it is saved under a new name, so that is the signal
# this listens to, and a read whose file has not moved is skipped.
class EditorPageEditorconfig < EditorPageSettingsProvider
  BASENAME = '.editorconfig'

  # The keys upstream's shim keeps, with the type it reads them as.
  INTEGER_KEYS = %w[tab_width max_line_length indent_size].freeze
  BOOLEAN_KEYS = %w[insert_final_newline trim_trailing_whitespace].freeze

  def initialize
    super()

    @path = nil
    @properties = {}
  end

  def document=(document)
    unless document.equal?(@document)
      super
      document&.signal_connect('saved') { reload }
      reload
    end
  end

  def tab_width = @properties['tab_width']

  def right_margin_position = @properties['max_line_length']

  def indent_width = @properties['indent_size']

  def implicit_trailing_newline = @properties['insert_final_newline']

  # Upstream reads "tab" as tabs and anything else — "space" included — as
  # spaces, which is what the comparison below does too.
  def insert_spaces_instead_of_tabs
    @properties['indent_style'].then do |style|
      unless style.nil?
        style != 'tab'
      end
    end
  end

  # Reads the .editorconfig files covering the document's file. Only a local
  # file has a path to walk up from, which is the one case upstream's shim
  # supports as well.
  def reload
    @document&.file&.path.then do |path|
      unless path == @path
        @path = path
        @properties = {}

        if path
          @properties = self.class.read(path)
        end

        emit_changed
      end
    end
  end

  # The properties that apply to one file, as the five keys upstream keeps.
  def self.read(path)
    File.expand_path(path).then do |absolute|
      collect(File.dirname(absolute)).reverse.each_with_object({}) do |(directory, sections), properties|
        sections.each do |(pattern, declarations)|
          if matches?(pattern, directory, absolute)
            properties.merge!(declarations)
          end
        end
      end.then { |properties| normalize(properties) }
    end
  end

  # The .editorconfig files from the file's own directory upwards, nearest
  # first, stopping at the one that declares itself the root.
  def self.collect(directory)
    [].tap do |found|
      current = directory
      rooted = false

      until rooted || current.nil?
        File.join(current, BASENAME).then do |candidate|
          if File.file?(candidate)
            parse(candidate).then do |(root, sections)|
              found << [current, sections]
              rooted = root
            end
          end
        end

        File.dirname(current).then do |parent|
          if parent == current
            current = nil
          else
            current = parent
          end
        end
      end
    end
  end

  # One file, as [root?, [[pattern, declarations], …]]. The preamble before
  # the first section holds the "root" key and nothing else that matters.
  def self.parse(file)
    root = false
    sections = []
    current = nil

    File.readlines(file, chomp: true).each do |line|
      line.strip.then do |stripped|
        case stripped
        when /\A[#;]/, ''
          nil
        when /\A\[(.*)\]\z/
          current = {}
          sections << [Regexp.last_match(1), current]
        when /\A([^=:]+)[=:](.*)\z/
          declaration(Regexp.last_match(1), Regexp.last_match(2)).then do |(key, value)|
            if current
              current[key] = value
            elsif key == 'root'
              root = value == 'true'
            end
          end
        end
      end
    end

    [root, sections]
  rescue StandardError
    [false, []]
  end

  # Keys are case-insensitive, and so are the values of the keys this reads.
  def self.declaration(key, value)
    [key.strip.downcase, value.strip.downcase]
  end

  # True when a section's pattern covers the file. A pattern with a slash in
  # it is relative to the directory holding the .editorconfig; one without can
  # match at any depth below it.
  def self.matches?(pattern, directory, path)
    relative(directory, path).then do |candidate|
      unless candidate.nil?
        glob(pattern).match?(candidate)
      end
    end
  end

  def self.relative(directory, path)
    directory.then do |root|
      if path.start_with?("#{root}/")
        path[(root.length + 1)..]
      elsif root == '/'
        path[1..]
      end
    end
  end

  # The pattern as a regular expression over the path relative to the
  # .editorconfig's directory.
  def self.glob(pattern)
    pattern.delete_prefix('!').then do |body|
      if body.include?('/')
        Regexp.new("\\A/?#{translate(body.delete_prefix('/'))}\\z")
      else
        Regexp.new("\\A(?:.*/)?#{translate(body)}\\z")
      end
    end
  end

  # The glob syntax .editorconfig uses: "*" within one path element, "**"
  # across them, "?", "[seq]", "[!seq]", "{a,b}" and "{n..m}".
  def self.translate(pattern)
    (+'').tap do |source|
      index = 0

      while index < pattern.length
        consume(pattern, index).then do |(fragment, width)|
          source << fragment
          index += width
        end
      end
    end
  end

  # One glob element, as [regexp fragment, characters consumed].
  def self.consume(pattern, index)
    case pattern[index..]
    when /\A\*\*/ then ['.*', 2]
    when /\A\*/ then ['[^/]*', 1]
    when /\A\?/ then ['[^/]', 1]
    when /\A\[(!?)([^\]]+)\]/ then bracket(Regexp.last_match(1), Regexp.last_match(2))
    when /\A\{(\d+)\.\.(\d+)\}/ then numeric_range(Regexp.last_match(1), Regexp.last_match(2))
    when /\A\{([^}]*)\}/ then alternation(Regexp.last_match(1))
    else [Regexp.escape(pattern[index]), 1]
    end
  end

  def self.bracket(negation, body)
    negated = negation == '!'

    if negated
      ["[^#{body}]", body.length + 3]
    else
      ["[#{body}]", body.length + 2]
    end
  end

  def self.numeric_range(from, to)
    Range.new(from.to_i, to.to_i).then do |range|
      ["(?:#{range.map { |number| Regexp.escape(number.to_s) }.join('|')})", from.length + to.length + 4]
    end
  end

  def self.alternation(body)
    body.split(',', -1).then do |choices|
      ["(?:#{choices.map { |choice| translate(choice) }.join('|')})", body.length + 2]
    end
  end

  # The five keys upstream keeps, in the types it keeps them as, with the
  # specification's two rules that tie indentation to the tab width.
  def self.normalize(properties)
    properties.slice(*(INTEGER_KEYS + BOOLEAN_KEYS + ['indent_style'])).then do |kept|
      resolve_indent_size(kept).then do |resolved|
        resolved.filter_map { |key, value| typed(key, value) }.to_h
      end
    end
  end

  def self.resolve_indent_size(properties)
    properties.dup.tap do |resolved|
      if resolved['indent_size'] == 'tab'
        resolved['indent_size'] = resolved['tab_width']
      end

      if !resolved.key?('tab_width') && resolved['indent_size'].to_s.match?(/\A\d+\z/)
        resolved['tab_width'] = resolved['indent_size']
      end
    end
  end

  def self.typed(key, value)
    case key
    when *INTEGER_KEYS
      if value.to_s.match?(/\A\d+\z/)
        [key, value.to_i]
      end
    when *BOOLEAN_KEYS then [key, value == 'true']
    else [key, value]
    end
  end
end
