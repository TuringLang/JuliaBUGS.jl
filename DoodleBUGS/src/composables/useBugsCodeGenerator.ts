import { computed } from 'vue';
import type { Ref } from 'vue';
import type { GraphElement, GraphNode, GraphEdge } from '../types';

/**
 * Composable that generates BUGS model code from graph elements.
 * @param elements - A ref to the graph elements.
 */
export function useBugsCodeGenerator(elements: Ref<GraphElement[]>) {
  const generatedCode = computed(() => {
    const nodes = elements.value.filter(el => el.type === 'node') as GraphNode[];
    const edges = elements.value.filter(el => el.type === 'edge') as GraphEdge[];
    const nodeMap = new Map(nodes.map(n => [n.id, n]));

    if (nodes.length === 0) {
      return 'model {\n  # Your model will appear here...\n}';
    }

    // Topological Sort (Kahn's algorithm) to determine node definition order.
    const nodeInDegree: { [key: string]: number } = {};
    const adjacencyList: { [key: string]: string[] } = {};
    nodes.forEach(node => {
      nodeInDegree[node.id] = 0;
      adjacencyList[node.id] = [];
    });
    edges.forEach(edge => {
      if (adjacencyList[edge.source] && nodeInDegree[edge.target] !== undefined) {
        adjacencyList[edge.source].push(edge.target);
        nodeInDegree[edge.target]++;
      }
    });
    const queue = nodes.filter(node => nodeInDegree[node.id] === 0).map(n => n.id);
    const sortedNodeIds: string[] = [];
    while (queue.length > 0) {
      const currentNodeId = queue.shift()!;
      sortedNodeIds.push(currentNodeId);
      adjacencyList[currentNodeId]?.forEach(childNodeId => {
        if (nodeInDegree[childNodeId] !== undefined) {
          nodeInDegree[childNodeId]--;
          if (nodeInDegree[childNodeId] === 0) {
            queue.push(childNodeId);
          }
        }
      });
    }

    interface TreeMember {
      id: string;
      type: 'node' | 'plate';
      children: TreeMember[];
    }
    const treeRoot: TreeMember = { id: 'root', type: 'plate', children: [] };
    const treeMemberMap = new Map<string, TreeMember>([['root', treeRoot]]);

    nodes.forEach(node => {
      treeMemberMap.set(node.id, { id: node.id, type: node.nodeType === 'plate' ? 'plate' : 'node', children: [] });
    });

    nodes.forEach(node => {
      const parentId = node.parent || 'root';
      const parentMember = treeMemberMap.get(parentId);
      const childMember = treeMemberMap.get(node.id);
      if (parentMember && childMember) {
        parentMember.children.push(childMember);
      }
    });

    const generateCodeRecursive = (member: TreeMember, indentLevel: number): string[] => {
      const lines: string[] = [];
      const indent = '  '.repeat(indentLevel);

      const sortedChildren = member.children.sort((a, b) => {
        return sortedNodeIds.indexOf(a.id) - sortedNodeIds.indexOf(b.id);
      });

      sortedChildren.forEach(child => {
        const childNode = nodeMap.get(child.id);
        if (!childNode) return;

        if (child.type === 'plate') {
          lines.push(`${indent}for (${childNode.loopVariable} in ${childNode.loopRange}) {`);
          lines.push(...generateCodeRecursive(child, indentLevel + 1));
          lines.push(`${indent}}`);
        } else {
          const nodeName = childNode.indices ? `${childNode.name}[${childNode.indices}]` : childNode.name;

          if (childNode.nodeType === 'stochastic' || childNode.nodeType === 'observed') {
            const params = Object.keys(childNode)
              .filter(key => key.startsWith('param') && childNode[key as keyof GraphNode] && String(childNode[key as keyof GraphNode]).trim() !== '')
              .map(key => String(childNode[key as keyof GraphNode]))
              .join(', ');
            lines.push(`${indent}${nodeName} ~ ${childNode.distribution}(${params})`);
          } else if (childNode.nodeType === 'deterministic' && childNode.equation) {
            lines.push(`${indent}${nodeName} <- ${childNode.equation}`);
          }
        }
      });
      return lines;
    };

    const finalCodeLines = generateCodeRecursive(treeRoot, 1);

    return ['model {', ...finalCodeLines, '}'].join('\n');
  });

  return {
    generatedCode,
  };
}
