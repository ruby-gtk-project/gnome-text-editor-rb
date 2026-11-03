# frozen_string_literal: true

# Drives the per-document settings stack and the editor's word boundaries
# without a user: builds documents whose language, .editorconfig and modelines
# disagree, and checks which setting wins. Run with
#   nix develop --command xvfb-run -a ruby test/drive_page_settings.rb
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'tmpdir'
require 'editor_document'
require 'editor_page_settings'
require 'editor_settings'
require 'editor_source_iter'

Dir.mktmpdir('gnome-text-editor-rb') do |dir|
  failures = []

  check = lambda do |label, &block|
    block.call
    puts "ok   #{label}"
  rescue StandardError => e
    failures << "#{label}: #{e.class}: #{e.message}"
    puts "FAIL #{label}: #{e.class}: #{e.message}"
    puts e.backtrace.first(5).map { |line| "       #{line}" }
  end

  # The settings the stack sits on. The JSON path keeps a checkout without the
  # compiled schema from falling over; with the schema installed these are the
  # user's own preferences, which the drive only reads.
  settings = EditorSettings.new(path: File.join(dir, 'settings.json'))

  document = lambda do |path, text|
    File.write(path, text)
    EditorDocument.new_for_file(Gio::File.new_for_path(path)).tap do |doc|
      doc.load do |error|
        if error
          raise error
        end
      end
    end
  end

  stack = ->(doc) { EditorPageSettings.new(doc, settings: settings).build }

  expect = lambda do |label, actual, wanted|
    unless actual == wanted
      raise "#{label} is #{actual.inspect}, wanted #{wanted.inspect}"
    end
  end

  check.call('language guessed from the file name') do
    document.call(File.join(dir, 'thing.rb'), "puts 1\n").then do |doc|
      expect.call('language_id', doc.language_id, 'ruby')
    end
  end

  check.call('per-language defaults') do
    stack.call(document.call(File.join(dir, 'defaults.rb'), "puts 1\n")).then do |page_settings|
      expect.call('tab_width', page_settings.tab_width, 2)
      expect.call('insert_spaces', page_settings.insert_spaces_instead_of_tabs, true)
      expect.call('right_margin_position', page_settings.right_margin_position, 80)
      expect.call('implicit_trailing_newline', page_settings.implicit_trailing_newline, true)
    end
  end

  project = File.join(dir, 'project')
  Dir.mkdir(project)
  File.write(
    File.join(project, '.editorconfig'),
    <<~CONFIG,
      root = true

      [*]
      indent_style = tab
      tab_width = 3
      insert_final_newline = false

      [*.rb]
      indent_size = 7
      max_line_length = 120
    CONFIG
  )

  check.call('.editorconfig beats the defaults') do
    stack.call(document.call(File.join(project, 'covered.rb'), "x = 1\n")).then do |page_settings|
      expect.call('tab_width', page_settings.tab_width, 3)
      expect.call('indent_width', page_settings.indent_width, 7)
      expect.call('insert_spaces', page_settings.insert_spaces_instead_of_tabs, false)
      expect.call('right_margin_position', page_settings.right_margin_position, 120)
      expect.call('implicit_trailing_newline', page_settings.implicit_trailing_newline, false)
    end
  end

  check.call('vim modeline beats the .editorconfig') do
    document.call(File.join(project, 'modeline.rb'), "# vim: set ts=5 sw=5 et tw=66:\nx = 1\n").then do |doc|
      stack.call(doc).then do |page_settings|
        expect.call('tab_width', page_settings.tab_width, 5)
        expect.call('indent_width', page_settings.indent_width, 5)
        expect.call('insert_spaces', page_settings.insert_spaces_instead_of_tabs, true)
        expect.call('right_margin_position', page_settings.right_margin_position, 66)
        expect.call('show_right_margin', page_settings.show_right_margin, true)
      end
    end
  end

  check.call('emacs modeline, with its language mapping') do
    document.call(
      File.join(dir, 'emacs.txt'),
      "-*- mode: C++; tab-width: 6; indent-tabs-mode: nil -*-\nint main () {}\n",
    ).then do |doc|
      stack.call(doc).then do |page_settings|
        expect.call('tab_width', page_settings.tab_width, 6)
        expect.call('insert_spaces', page_settings.insert_spaces_instead_of_tabs, true)
        expect.call('language_id', doc.language_id, 'cpp')
      end
    end
  end

  check.call('kate modeline') do
    document.call(
      File.join(dir, 'kate.txt'),
      "// kate: space-indent on; indent-width 4; word-wrap-column 70; syntax javascript;\n",
    ).then do |doc|
      stack.call(doc).then do |page_settings|
        expect.call('indent_width', page_settings.indent_width, 4)
        expect.call('insert_spaces', page_settings.insert_spaces_instead_of_tabs, true)
        expect.call('right_margin_position', page_settings.right_margin_position, 70)
        expect.call('language_id', doc.language_id, 'javascript')
      end
    end
  end

  check.call('a setting the user chose for one document wins') do
    stack.call(document.call(File.join(dir, 'override.rb'), "x = 1\n")).then do |page_settings|
      changed = []
      page_settings.on_changed { |keys| changed.concat(keys) }
      page_settings.override(:tab_width, 11)

      expect.call('tab_width', page_settings.tab_width, 11)
      expect.call('changed', changed, [:tab_width])
      expect.call('overridden?', page_settings.overridden?(:tab_width), true)
    end
  end

  check.call('word boundaries count the underscore and punctuation runs') do
    Gtk::TextBuffer.new.tap do |buffer|
      buffer.text = "hello world_foo ---- bar\n"

      EditorSourceIter.extend_selection_word(buffer.get_iter_at(offset: 8)).then do |(from, to)|
        expect.call('identifier', buffer.get_text(from, to, true), 'world_foo')
      end

      EditorSourceIter.extend_selection_word(buffer.get_iter_at(offset: 17)).then do |(from, to)|
        expect.call('punctuation', buffer.get_text(from, to, true), '----')
      end

      expect.call(
        'forward word end',
        EditorSourceIter.forward_visible_word_end(buffer.get_iter_at(offset: 5)).offset,
        15,
      )
      expect.call(
        'backward word start',
        EditorSourceIter.backward_visible_word_start(buffer.get_iter_at(offset: 15)).offset,
        6,
      )
      expect.call(
        'three words forward',
        EditorSourceIter.forward_visible_word_ends(buffer.get_iter_at(offset: 0), 3).offset,
        20,
      )
    end
  end

  puts(failures.empty? ? 'ALL OK' : "FAILURES: #{failures.length}")
  exit(failures.empty? ? 0 : 1)
end
