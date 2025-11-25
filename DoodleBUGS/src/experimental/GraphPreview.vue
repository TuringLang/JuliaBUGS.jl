<script setup lang="ts">
import { onMounted, ref, watch, onBeforeUnmount } from 'vue';
import cytoscape from 'cytoscape';
import type { GraphElement, GraphNode } from '../../types';

const props = defineProps<{
  elements: GraphElement[];
  graphId: string;
  // Grid props for per-graph overrides
  isGridEnabled?: boolean;
  gridSize?: number;
  gridStyle?: string; // 'dots' | 'lines'
}>();

const container = ref<HTMLElement | null>(null);
let cy: cytoscape.Core | null = null;

const formatElements = (elements: GraphElement[]) => {
  return elements.map(el => {
    if (el.type === 'node') {
      const node = el as GraphNode;
      const classes = node.nodeType === 'plate' ? 'plate' : '';
      
      // Prepare label
      let label = node.name || node.id;
      if (node.indices) label += `[${node.indices}]`;
      if (node.nodeType === 'plate') {
         label = `for(${node.loopVariable || 'i'} in ${node.loopRange || '1:N'})`;
      }

      return {
        group: 'nodes' as const,
        data: { ...node, label },
        position: node.position,
        classes: classes
      };
    } else {
      return {
        group: 'edges' as const,
        data: { ...el }
      };
    }
  });
};

const updateGraph = () => {
  if (!cy) return;
  
  cy.batch(() => {
    cy?.elements().remove();
    const formatted = formatElements(props.elements);
    if (formatted.length > 0) {
      cy?.add(formatted);
    }
  });
  
  // Only run layout/fit if we have elements
  if (props.elements.length > 0) {
    // Use preset because elements have positions
    cy.layout({ name: 'preset' }).run();
    cy.fit(undefined, 20);
  }
};

const initCy = () => {
  if (!container.value) return;

  cy = cytoscape({
    container: container.value,
    style: [
      {
        selector: 'node',
        style: {
          'background-color': '#e0e0e0', 
          'border-color': '#555', 
          'border-width': 2,
          'label': 'data(label)',
          'text-valign': 'center', 
          'text-halign': 'center', 
          'padding': '10px', 
          'font-size': '10px',
          'text-wrap': 'wrap', 
          'text-max-width': '80px', 
          'height': '60px', 
          'width': '60px',
          'line-height': 1.2, 
          'border-style': 'solid'
        },
      },
      {
        selector: 'node[nodeType="plate"]',
        style: {
          'background-color': '#f0f8ff', 
          'border-color': '#4682b4', 
          'border-style': 'dashed',
          'shape': 'round-rectangle', 
          'text-valign': 'top', // Plates often need labels at top
          'text-halign': 'center'
        },
      },
      {
        selector: ':parent', // Cytoscape parent selector (compound nodes)
        style: { 
          'text-valign': 'top', 
          'text-halign': 'center', 
          'padding': '15px', 
          'background-opacity': 0.2 
        },
      },
      {
        selector: 'node[nodeType="stochastic"]',
        style: { 'background-color': '#ffe0e0', 'border-color': '#dc3545', 'shape': 'ellipse' },
      },
      {
        selector: 'node[nodeType="deterministic"]',
        style: { 'background-color': '#e0ffe0', 'border-color': '#28a745', 'shape': 'triangle' },
      },
      {
        selector: 'node[nodeType="constant"]',
        style: { 'background-color': '#e9ecef', 'border-color': '#6c757d', 'shape': 'rectangle' },
      },
      {
        selector: 'node[nodeType="observed"]',
        style: { 'background-color': '#e0f0ff', 'border-color': '#007bff', 'border-style': 'dashed', 'shape': 'ellipse' },
      },
      {
        selector: 'edge',
        style: {
          'width': 2,
          'line-color': '#a0a0a0',
          'target-arrow-color': '#a0a0a0',
          'target-arrow-shape': 'triangle',
          'curve-style': 'bezier'
        }
      }
    ],
    layout: {
      name: 'preset'
    },
    autoungrabify: true,
    autounselectify: true,
    userZoomingEnabled: false,
    userPanningEnabled: false,
    boxSelectionEnabled: false
  });

  updateGraph();
};

let resizeObserver: ResizeObserver | null = null;

watch(() => props.elements, () => {
  updateGraph();
}, { deep: true });

onMounted(() => {
  initCy();
  if (container.value) {
    resizeObserver = new ResizeObserver(() => {
      if (cy) {
        cy.resize();
        if (props.elements.length > 0) {
          cy.fit(undefined, 20);
        }
      }
    });
    resizeObserver.observe(container.value);
  }
});

onBeforeUnmount(() => {
  if (resizeObserver) {
    resizeObserver.disconnect();
    resizeObserver = null;
  }
  if (cy) {
    cy.destroy();
    cy = null;
  }
});
</script>

<template>
  <div 
    class="graph-preview" 
    ref="container"
    :class="{
        'grid-dots': isGridEnabled && gridStyle === 'dots', 
        'grid-lines': isGridEnabled && gridStyle === 'lines'
    }"
    :style="isGridEnabled ? { backgroundSize: `${gridSize}px ${gridSize}px` } : {}"
  ></div>
</template>

<style scoped>
.graph-preview {
  width: 100%;
  height: 100%;
  background-color: var(--theme-bg-canvas);
  /* Ensure it expands */
  flex-grow: 1;
}

.graph-preview.grid-dots {
  background-image: radial-gradient(circle, var(--theme-grid-line) 1px, transparent 1px);
}

.graph-preview.grid-lines {
  background-image:
    linear-gradient(to right, var(--theme-grid-line) 1px, transparent 1px),
    linear-gradient(to bottom, var(--theme-grid-line) 1px, transparent 1px);
}
</style>
