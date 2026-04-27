# frozen_string_literal: true

module Phaser
  # Acyclicity check for a flavor's precedent-rule graph.
  #
  # Edges run predecessor_type -> subject_type (the subject must appear
  # in a strictly later phase than the predecessor). A cycle in this
  # graph would make the flavor's ordering constraints unsatisfiable, so
  # the loader rejects the catalog at load time
  # (data-model.md "PrecedentRule" Validation rules; T019).
  #
  # The check uses Kahn's-algorithm sketch: repeatedly strip nodes whose
  # indegree has reached zero. If any nodes remain after the queue
  # empties, the graph contains a cycle.
  module PrecedentRuleGraph
    module_function

    # Returns true when the rule list defines an acyclic dependency
    # graph; false otherwise.
    def acyclic?(rules)
      adjacency, indegree = build_graph(rules)
      visited = topo_visit_count(adjacency, indegree)
      visited == indegree.size
    end

    # Build the (adjacency, indegree) representation of the graph. Both
    # endpoints are materialized in `indegree` so the topo-sort
    # accounting covers every node, not only the subjects on the
    # receiving end of an edge.
    def build_graph(rules)
      adjacency = Hash.new { |h, k| h[k] = [] }
      indegree = {}

      rules.each do |rule|
        adjacency[rule['predecessor_type']] << rule['subject_type']
        indegree[rule['subject_type']] = (indegree[rule['subject_type']] || 0) + 1
        indegree[rule['predecessor_type']] ||= 0
      end

      [adjacency, indegree]
    end

    def topo_visit_count(adjacency, indegree)
      queue = indegree.select { |_, deg| deg.zero? }.keys
      visited = 0
      until queue.empty?
        node = queue.shift
        visited += 1
        adjacency[node].each do |neighbor|
          indegree[neighbor] -= 1
          queue << neighbor if indegree[neighbor].zero?
        end
      end
      visited
    end
  end
end
