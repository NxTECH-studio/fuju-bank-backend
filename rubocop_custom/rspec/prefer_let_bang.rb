class RuboCop::Cop::RSpec::PreferLetBang < RuboCop::Cop::Base
  extend RuboCop::Cop::AutoCorrector

  MSG = "`let` の代わりに `let!` を使用してください".freeze

  def_node_matcher :let_node, "(block (send nil? :let $(sym _)) ...)"

  def on_block(node)
    return unless let_node(node)

    add_offense(node.send_node.loc.selector) do |corrector|
      corrector.replace(node.send_node.loc.selector, "let!")
    end
  end
  alias on_numblock on_block
end
