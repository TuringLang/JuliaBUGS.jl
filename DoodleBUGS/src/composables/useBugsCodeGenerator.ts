import { computed } from 'vue';
import type { Ref } from 'vue';
import type { GraphElement, GraphNode, GraphEdge, ModelData } from '../types';

/**
 * Composable that generates BUGS model code from graph elements.
 * This version correctly handles nested plates and substitutes constant values.
 * @param elements - A ref to the graph elements.
 * @param modelData - A ref to the parsed model data.
 */
export function useBugsCodeGenerator(elements: Ref<GraphElement[]>, modelData: Ref<ModelData>) {
  const generatedCode = computed(() => {
    const nodes = elements.value.filter(el => el.type === 'node') as GraphNode[];
    const edges = elements.value.filter(el => el.type === 'edge') as GraphEdge[];
    const dataKeys = new Set(Object.keys(modelData.value.data));
    const nodeMap = new Map(nodes.map(n => [n.id, n]));

    if (nodes.length === 0) {
      return 'model {\n  # Your model will appear here...\n}';
    }

    // --- Topological Sort (Kahn's algorithm) ---
    const inDegree: { [key: string]: number } = {};
    const adj: { [key: string]: string[] } = {};
    nodes.forEach(node => {
      inDegree[node.id] = 0;
      adj[node.id] = [];
    });
    edges.forEach(edge => {
      if (adj[edge.source] && inDegree[edge.target] !== undefined) {
        adj[edge.source].push(edge.target);
        inDegree[edge.target]++;
      }
    });
    const queue = nodes.filter(node => inDegree[node.id] === 0).map(n => n.id);
    const sortedNodeIds: string[] = [];
    while (queue.length > 0) {
      const u = queue.shift()!;
      sortedNodeIds.push(u);
      adj[u]?.forEach(vId => {
        if (inDegree[vId] !== undefined) {
          inDegree[vId]--;
          if (inDegree[vId] === 0) {
            queue.push(vId);
          }
        }
      });
    }

    // --- Build a Tree Structure for Plates and Nodes ---
    interface TreeMember {
      id: string;
      type: 'node' | 'plate';
      children: TreeMember[];
    }
    const treeRoot: TreeMember = { id: 'root', type: 'plate', children: [] };
    const treeMemberMap = new Map<string, TreeMember>([['root', treeRoot]]);

    nodes.forEach(node => {
      if (node.nodeType === 'plate') {
        treeMemberMap.set(node.id, { id: node.id, type: 'plate', children: [] });
      } else {
        treeMemberMap.set(node.id, { id: node.id, type: 'node', children: [] });
      }
    });

    nodes.forEach(node => {
      const parentId = node.parent || 'root';
      const parentMember = treeMemberMap.get(parentId);
      const childMember = treeMemberMap.get(node.id);
      if (parentMember && childMember) {
        parentMember.children.push(childMember);
      }
    });

    // --- Recursive Code Generation Function ---
    const generateCodeRecursive = (member: TreeMember, indentLevel: number): string[] => {
      let lines: string[] = [];
      const indent = '  '.repeat(indentLevel);

      // Sort children based on the topological sort order
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
          // It's a regular node
          const nodeName = childNode.indices ? `${childNode.name}[${childNode.indices}]` : childNode.name;
          
          if (childNode.nodeType === 'stochastic' || childNode.nodeType === 'observed') {
            const params = [childNode.param1, childNode.param2, childNode.param3]
                .filter(p => p && String(p).trim() !== '')
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

    const modelString = [
      'model {',
      ...finalCodeLines,
      '}'
    ].join('\n');
    
    return modelString;
  });

  return {
    generatedCode,
  };
}
