# frozen_string_literal: true

require 'adwaita'

# EditorPath expands and collapses filesystem paths for display.
#
# Ported from upstream's src/editor-path.c. Upstream leans on wordexp(3) to
# expand "~" and shell variables; Ruby's File.expand_path does the same job for
# "~" and the relative-to-$HOME fallback, and ENV covers the variable case, so
# the two helpers below cover what upstream's _editor_path_expand and
# _editor_path_collapse are used for.
module EditorPath
  # Early versions of the document portal appended this to the host path.
  PORTAL_SUFFIX = '\\x00'
  HOST_PATH_ATTRIBUTE = 'xattr::document-portal.host-path'
  PORTAL_NAME = 'Document Portal'

  class << self
    # Expands "~", "$VAR" and "${VAR}", then makes the result absolute against
    # the home directory, exactly as upstream does after wordexp.
    def expand(path)
      path.then do |value|
        if value.nil?
          nil
        else
          substitute(value).then do |expanded|
            if expanded.start_with?('~')
              File.expand_path(expanded)
            elsif expanded.start_with?(File::SEPARATOR)
              expanded
            else
              File.join(Dir.home, expanded)
            end
          end
        end
      end
    end

    # The inverse of #expand: $HOME becomes "~/", and a path below $HOME keeps
    # its tail under "~".
    def collapse(path)
      path.then do |value|
        if value.nil?
          nil
        elsif (expanded = expand(value)) == Dir.home
          '~/'
        elsif expanded.start_with?("#{Dir.home}#{File::SEPARATOR}")
          File.join('~', expanded.delete_prefix(Dir.home))
        else
          expanded
        end
      end
    end

    # The path a portal-exported file has on the host, for display. Falls back
    # to the same "Document Portal" fallback upstream uses.
    def portal_host_path(file)
      host_path(file).then do |value|
        if value.nil?
          PORTAL_NAME
        else
          collapse(value.delete_suffix(PORTAL_SUFFIX))
        end
      end
    end

    private

      def host_path(file)
        file.query_info(HOST_PATH_ATTRIBUTE, :none)
            .get_attribute_string(HOST_PATH_ATTRIBUTE)
      rescue StandardError
        nil
      end

      def substitute(value)
        value.gsub(/\$\{(\w+)\}|\$(\w+)/) { ENV.fetch(Regexp.last_match(1) || Regexp.last_match(2), '') }
      end
  end
end
