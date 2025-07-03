import { watch } from 'vue';
import type { Core } from 'cytoscape';
import type { GraphElement, GraphNode, GraphEdge } from '../types';

export function useGraphSync(getCyInstance: () => Core | null, elements: GraphElement[]) {
  watch(elements, (newElements) => {
    const cy = getCyInstance();
    if (!cy) {
      console.warn('Cytoscape instance not available for synchronization.');
      return;
    }

    const newElementIds = new Set(newElements.map(el => el.id));

    cy.batch(() => {
        cy.elements().forEach(cyEl => {
          if (!newElementIds.has(cyEl.id())) {
              cyEl.remove();
          }
        });

        newElements.forEach(newEl => {
          const existingCyEl = cy.getElementById(newEl.id);

          if (existingCyEl.empty()) {
              if (newEl.type === 'node') {
                const nodeData = newEl as GraphNode;
                cy.add({
                    group: 'nodes',
                    data: nodeData,
                    position: nodeData.position
                });
              } else if (newEl.type === 'edge') {
                const edgeData = newEl as GraphEdge;
                cy.add({
                    group: 'edges',
                    data: {
                        id: edgeData.id,
                        name: edgeData.name,
                        source: edgeData.source,
                        target: edgeData.target,
                    }
                });
              }
          } else {
              existingCyEl.data(newEl);
              if (newEl.type === 'node') {
                const newNodePos = (newEl as GraphNode).position;
                const currentCyPos = existingCyEl.position();
                if (newNodePos.x !== currentCyPos.x || newNodePos.y !== currentCyPos.y) {
                    existingCyEl.position(newNodePos);
                }
              }
          }
        });
    });
  }, { deep: true });
}
