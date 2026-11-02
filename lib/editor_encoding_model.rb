# frozen_string_literal: true

require 'adwaita'

# EditorEncoding is one character set the editor can read and write a file in;
# EditorEncodingModel is the list of them.
#
# Ported from upstream's src/editor-encoding-model.c, which wraps
# GtkSourceEncoding and gets its list from gtk_source_encoding_get_all(). There
# is no GtkSourceView here, so the table below is the same set of charsets,
# with the same region names GtkSourceView gives them, filtered down to the
# ones Ruby's iconv bindings can actually transcode on this machine — an
# encoding the list offers is one the document can really be saved in.
class EditorEncoding
  attr_reader :charset, :region, :index

  def initialize(charset, region, index)
    @charset = charset
    @region = region
    @index = index
  end

  # "Unicode (UTF-8)" — GtkSourceEncoding's to_string format.
  def name = @region.empty? ? @charset : "#{@region} (#{@charset})"

  def ruby_encoding = Encoding.find(@charset)

  # Decodes bytes read from disk, replacing anything invalid so a mis-detected
  # encoding still opens; the second value says whether a replacement happened,
  # which is what drives the info bar's "Invalid Characters Detected".
  def decode(bytes)
    bytes.dup.force_encoding(ruby_encoding).then do |text|
      if text.valid_encoding?
        [text.encode(Encoding::UTF_8), false]
      else
        [text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�"), true]
      end
    end
  end

  # Encodes UTF-8 text for writing. Characters the charset cannot represent are
  # replaced rather than raising, matching GtkSourceFileSaver's fallback.
  def encode(text) = text.encode(ruby_encoding, invalid: :replace, undef: :replace)

  private

    # Transcodes through UTF-16 rather than calling String#encode straight to
    # UTF-8. A conversion whose source and target encodings match is a no-op
    # in Ruby, so decoding bytes that are already tagged UTF-8 would never be
    # validated — and bytes read through a Gio stream come back with their
    # character range already cached, so String#valid_encoding? cannot be
    # trusted to notice either. Going via UTF-16 forces a real conversion,
    # which raises on invalid input and is lossless for valid input.
    def transcode(bytes, fallback: false)
      if fallback
        options = { invalid: :replace, undef: :replace, replace: "\uFFFD" }
      else
        options = {}
      end

      bytes.dup
           .force_encoding(Encoding::ASCII_8BIT)
           .encode(Encoding::UTF_16LE, ruby_encoding, **options)
           .encode(Encoding::UTF_8)
    end
end

class EditorEncodingModel
  # charset, region name. The order and the names are GtkSourceView's.
  CHARSETS = [
    ['UTF-8', 'Unicode'],
    ['UTF-16', 'Unicode'],
    ['UTF-16BE', 'Unicode'],
    ['UTF-16LE', 'Unicode'],
    ['UTF-32', 'Unicode'],
    ['UTF-7', 'Unicode'],
    ['ISO-8859-1', 'Western'],
    ['ISO-8859-15', 'Western'],
    ['IBM850', 'Western'],
    ['Windows-1252', 'Western'],
    ['macRoman', 'Western'],
    ['ISO-8859-2', 'Central European'],
    ['IBM852', 'Central European'],
    ['Windows-1250', 'Central European'],
    ['macCentEuro', 'Central European'],
    ['ISO-8859-3', 'South European'],
    ['ISO-8859-4', 'Baltic'],
    ['ISO-8859-13', 'Baltic'],
    ['Windows-1257', 'Baltic'],
    ['ISO-8859-5', 'Cyrillic'],
    ['IBM855', 'Cyrillic'],
    ['KOI8-R', 'Cyrillic'],
    ['KOI8-U', 'Cyrillic/Ukrainian'],
    ['Windows-1251', 'Cyrillic'],
    ['macCyrillic', 'Cyrillic'],
    ['ISO-8859-6', 'Arabic'],
    ['Windows-1256', 'Arabic'],
    ['macArabic', 'Arabic'],
    ['ISO-8859-7', 'Greek'],
    ['Windows-1253', 'Greek'],
    ['macGreek', 'Greek'],
    ['ISO-8859-8', 'Hebrew Visual'],
    ['ISO-8859-8-I', 'Hebrew'],
    ['Windows-1255', 'Hebrew'],
    ['ISO-8859-9', 'Turkish'],
    ['IBM857', 'Turkish'],
    ['Windows-1254', 'Turkish'],
    ['macTurkish', 'Turkish'],
    ['ISO-8859-10', 'Nordic'],
    ['ISO-8859-14', 'Celtic'],
    ['ISO-8859-16', 'Romanian'],
    ['macRomania', 'Romanian'],
    ['Windows-1258', 'Vietnamese'],
    ['TIS-620', 'Thai'],
    ['macThai', 'Thai'],
    ['Shift_JIS', 'Japanese'],
    ['EUC-JP', 'Japanese'],
    ['ISO-2022-JP', 'Japanese'],
    ['Windows-31J', 'Japanese'],
    ['EUC-KR', 'Korean'],
    ['ISO-2022-KR', 'Korean'],
    ['Windows-949', 'Korean'],
    ['Big5', 'Chinese Traditional'],
    ['Big5-HKSCS', 'Chinese Traditional'],
    ['EUC-TW', 'Chinese Traditional'],
    ['GB2312', 'Chinese Simplified'],
    ['GBK', 'Chinese Simplified'],
    ['GB18030', 'Chinese Simplified'],
    ['ARMSCII-8', 'Armenian'],
    ['Georgian-Academy', 'Georgian'],
  ].freeze

  def self.default = @default ||= new

  def initialize
    @items = CHARSETS
             .select { |charset, _| supported?(charset) }
             .each_with_index
             .map { |(charset, region), index| EditorEncoding.new(charset, region, index) }
  end

  attr_reader :items

  def n_items = @items.length

  def get_item(position) = @items[position]

  def utf8 = get('UTF-8')

  def get(charset)
    charset.to_s.downcase.then do |needle|
      @items.find { |item| item.charset.downcase == needle }
    end
  end

  def string_list = Gtk::StringList.new(@items.map(&:name))

  # Upstream leans on GtkSourceFileLoader's candidate list: UTF-8 first, then
  # the locale charset, then Latin-1 as the encoding that never fails.
  def candidates
    [utf8, get(Encoding.default_external.name), get('ISO-8859-1')].compact.uniq
  end

  # Picks the first candidate that decodes the bytes without replacement, so
  # opening a Latin-1 file does not fill the buffer with U+FFFD.
  def detect(bytes)
    candidates.find { |encoding| !encoding.decode(bytes).last } || utf8
  end

  private

    def supported?(charset)
      Encoding.find(charset)
      true
    rescue ArgumentError
      false
    end
end
