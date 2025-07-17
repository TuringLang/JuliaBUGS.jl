import { computed } from 'vue';
import type { GraphElement, GraphNode, GraphEdge } from '../types';

/**
 * Composable that generates BUGS model code from graph elements.
 * Uses topological sorting to ensure proper declaration order.
 */
export function useBugsCodeGenerator(elements: () => GraphElement[]) {
  const generatedCode = computed(() => {
    const nodes = elements().filter(el => el.type === 'node') as GraphNode[];
    const edges = elements().filter(el => el.type === 'edge') as GraphEdge[];

    if (nodes.length === 0) {
      return 'model {\n  # Your model will appear here...\n}';
    }

    // Topological sort using Kahn's algorithm
    const inDegree: { [key: string]: number } = {};
    const adj: { [key: string]: string[] } = {};
    nodes.forEach(node => {
      inDegree[node.id] = 0;
      adj[node.id] = [];
    });

    edges.forEach(edge => {
      adj[edge.source]?.push(edge.target);
      if (inDegree[edge.target] !== undefined) {
        inDegree[edge.target]++;
      }
    });

    const queue = nodes.filter(node => inDegree[node.id] === 0).map(n => n.id);
    const sortedNodes: GraphNode[] = [];
    const nodeMap = new Map(nodes.map(n => [n.id, n]));

    while (queue.length > 0) {
      const u = queue.shift()!;
      const node = nodeMap.get(u);
      if (node) sortedNodes.push(node);

      adj[u]?.forEach(vId => {
        if (inDegree[vId] !== undefined) {
          inDegree[vId]--;
          if (inDegree[vId] === 0) {
            queue.push(vId);
          }
        }
      });
    }
    
    // Group nodes by their parent plate
    const nodesByPlate: { [key: string]: GraphNode[] } = { 'root': [] };
    sortedNodes.forEach(node => {
        if (node.nodeType === 'plate') return;
        const parentId = node.parent || 'root';
        if (!nodesByPlate[parentId]) {
            nodesByPlate[parentId] = [];
        }
        nodesByPlate[parentId].push(node);
    });

    let codeLines: string[] = [];

    const generateNodeCode = (node: GraphNode): string => {
        const parents = edges.filter(e => e.target === node.id).map(e => {
            const parentNode = nodeMap.get(e.source);
            return parentNode ? parentNode.name : 'undefined_parent';
        });

        const nodeName = node.indices ? `${node.name}[${node.indices}]` : node.name;

        if (node.nodeType === 'stochastic' || (node.nodeType === 'observed' && node.distribution)) {
            const params = parents.join(', ');
            return `  ${nodeName} ~ ${node.distribution}(${params})`;
        }
        if (node.nodeType === 'deterministic' && node.equation) {
            return `  ${nodeName} <- ${node.equation}`;
        }
        return '';
    };
    
    nodesByPlate['root'].forEach(node => {
        const line = generateNodeCode(node);
        if (line) codeLines.push(line);
    });

    sortedNodes.forEach(node => {
        if (node.nodeType === 'plate' && nodesByPlate[node.id]) {
            const plate = node;
            codeLines.push(`  for (${plate.loopVariable} in ${plate.loopRange}) {`);
            nodesByPlate[plate.id].forEach(childNode => {
                const line = generateNodeCode(childNode);
                if (line) codeLines.push(`  ${line}`);
            });
            codeLines.push('  }');
        }
    });

    return `model {\n${codeLines.join('\n')}\n}`;
  });

  return {
    generatedCode,
  };
}
