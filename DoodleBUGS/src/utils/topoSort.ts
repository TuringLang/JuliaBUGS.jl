import type { GraphNode, GraphEdge } from '../types'

/**
 * Topological sort (Kahn's algorithm) over graph nodes.
 * Returns node IDs in dependency order (parents before children).
 */
export function buildTopologicalOrder(nodes: GraphNode[], edges: GraphEdge[]): string[] {
  const nodeInDegree: Record<string, number> = {}
  const adjacencyList: Record<string, string[]> = {}
  nodes.forEach((node) => {
    nodeInDegree[node.id] = 0
    adjacencyList[node.id] = []
  })
  edges.forEach((edge) => {
    if (adjacencyList[edge.source] && nodeInDegree[edge.target] !== undefined) {
      adjacencyList[edge.source].push(edge.target)
      nodeInDegree[edge.target]++
    }
  })
  const queue = nodes.filter((n) => nodeInDegree[n.id] === 0).map((n) => n.id)
  const sorted: string[] = []
  while (queue.length > 0) {
    const id = queue.shift()!
    sorted.push(id)
    adjacencyList[id]?.forEach((child) => {
      if (nodeInDegree[child] !== undefined) {
        nodeInDegree[child]--
        if (nodeInDegree[child] === 0) queue.push(child)
      }
    })
  }
  return sorted
}
