# frozen_string_literal: true

require 'adwaita'

# EditorFocusChain moves focus along a list a widget keeps by hand, so Tab
# inside the search bar walks its entries and buttons in the order they read
# rather than the order they happen to be packed in.
#
# Ported from upstream's src/editor-focus-chain.c. Upstream calls
# _editor_focus_chain_focus_child from the search bar's GtkWidget::focus
# vfunc, with a GQueue of children; the Ruby bindings cannot override that
# vfunc, so the same function is called from a capture-phase key controller on
# the widget — the chain, the direction handling, the "start after whichever
# child has the focus" rule and the skipping of hidden or insensitive children
# are upstream's.
module EditorFocusChain
  FORWARD = %w[tab_forward right].freeze
  BACKWARD = %w[tab_backward left].freeze

  module_function

  # Focuses the next child along the chain and answers whether it took. A
  # direction that is neither forwards nor backwards is upstream's "not ours".
  def focus_child(widget, chain, direction)
    if forward?(direction) || backward?(direction)
      candidates(widget, chain, direction).then do |remaining|
        !remaining.find { |child| descendant_visible?(widget, child) && child.grab_focus }.nil?
      end
    else
      false
    end
  end

  # The chain in the direction asked for, starting after whichever child holds
  # the focus now.
  def candidates(widget, chain, direction)
    ordered(chain, direction).then do |ordered_chain|
      if contains_focus?(widget)
        ordered_chain.index { |child| contains_focus?(child) }.then do |index|
          if index.nil?
            ordered_chain
          else
            ordered_chain[(index + 1)..]
          end
        end
      else
        ordered_chain
      end
    end
  end

  def ordered(chain, direction)
    if forward?(direction)
      chain
    else
      chain.reverse
    end
  end

  def forward?(direction) = FORWARD.include?(name_of(direction))

  def backward?(direction) = BACKWARD.include?(name_of(direction))

  # A direction can arrive as the symbol the Ruby bindings use or as a
  # Gtk::DirectionType.
  def name_of(direction) = direction.to_s.downcase

  # True when the focus is on the widget itself or on anything inside it. The
  # focus GTK reports can be a widget's own inner text, which is why this asks
  # about ancestry rather than identity alone.
  def contains_focus?(widget)
    widget.root&.focus.then do |focus|
      if focus.nil?
        false
      else
        focus == widget || focus.ancestor?(widget)
      end
    end
  end

  # True when every widget from the descendant up to the container is visible
  # and sensitive, which is what makes a chain entry focusable at all.
  def descendant_visible?(widget, descendant)
    visible = true
    iter = descendant

    while iter && visible
      visible = iter.visible? && iter.child_visible? && iter.sensitive?

      if iter == widget
        iter = nil
      else
        iter = iter.parent
      end
    end

    visible
  end
end
