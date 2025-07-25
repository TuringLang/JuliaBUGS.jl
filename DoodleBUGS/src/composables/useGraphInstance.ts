import cytoscape from 'cytoscape';
import type { Core, ElementDefinition, NodeSingular, SingularElementReturnValue } from 'cytoscape';
import gridGuide from 'cytoscape-grid-guide';
import contextMenus from 'cytoscape-context-menus';
import dagre from 'cytoscape-dagre';
import fcose from 'cytoscape-fcose';
import compoundDragAndDrop from 'cytoscape-compound-drag-and-drop';
import svg from 'cytoscape-svg';

cytoscape.use(gridGuide);
cytoscape.use(contextMenus);
cytoscape.use(dagre);
cytoscape.use(fcose);
cytoscape.use(compoundDragAndDrop);
cytoscape.use(svg);

let cyInstance: Core | null = null;

interface ContextMenuEvent {
  target: SingularElementReturnValue;
}

export function useGraphInstance() {
  const initCytoscape = (container: HTMLElement, initialElements: ElementDefinition[]): Core => {
    if (cyInstance) {
      cyInstance.destroy();
      cyInstance = null;
    }

    const options: cytoscape.CytoscapeOptions = {
      container: container,
      elements: initialElements,
      style: [
        {
          selector: 'node',
          style: { 
            'background-color': '#e0e0e0', 'border-color': '#555', 'border-width': 2, 
            'label': (ele: NodeSingular) => {
                const name = ele.data('name');
                const indices = ele.data('indices');
                return indices ? `${name}[${indices}]` : name;
            },
            'text-valign': 'center', 'text-halign': 'center', 'padding': '10px', 'font-size': '10px', 
            'text-wrap': 'wrap', 'text-max-width': '80px', 'height': '60px', 'width': '60px', 
            'line-height': 1.2, 'border-style': 'solid', 'z-index': 10 
          },
        },
        {
          selector: 'node[nodeType="plate"]',
          style: { 
            'background-color': '#f0f8ff', 'border-color': '#4682b4', 'border-style': 'dashed', 
            'shape': 'round-rectangle', 'corner-radius': '10px',
            'label': (ele: NodeSingular) => `for(${ele.data('loopVariable')} in ${ele.data('loopRange')})`
          },
        },
        {
          selector: ':parent',
          style: { 'text-valign': 'top', 'text-halign': 'center', 'padding': '15px', 'background-opacity': 0.2, 'z-index': 5 },
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
          selector: 'node[?hasError]',
          style: { 'border-color': '#ffc107', 'border-width': 3, 'border-style': 'double' }
        },
        {
          selector: 'edge',
          style: {
            'width': 3,
            'line-color': '#a0a0a0',
            'target-arrow-color': '#a0a0a0',
            'target-arrow-shape': 'triangle',
            'curve-style': 'bezier',
            'z-index': 1,
          },
        },
        {
          selector: 'edge[name]',
          style: {
            'label': 'data(name)',
            'font-size': '8px',
            'text-rotation': 'autorotate',
            'text-background-opacity': 1,
            'text-background-color': '#ffffff',
            'text-background-padding': '3px',
            'text-border-width': 1,
            'text-border-color': '#ccc',
          }
        },
        {
          selector: 'edge[relationshipType="stochastic"]',
          style: { 'line-color': '#dc3545', 'target-arrow-color': '#dc3545', 'line-style': 'dashed' },
        },
        {
          selector: 'edge[relationshipType="deterministic"]',
          style: { 'line-color': '#28a745', 'target-arrow-color': '#28a745', 'line-style': 'solid' },
        },
        {
          selector: '.cy-selected',
          style: { 'border-width': 3, 'border-color': '#007acc', 'overlay-color': '#007acc', 'overlay-opacity': 0.2 },
        },
        {
            selector: '.cdnd-grabbed-node',
            style: { 'background-color': '#f1c40f', 'opacity': 0.7 }
        },
        {
            selector: '.cdnd-drop-target',
            style: { 'border-color': '#f1c40f', 'border-style': 'solid' }
        },
      ],
      layout: { name: 'preset' },
      minZoom: 0.1,
      maxZoom: 2,
      boxSelectionEnabled: true,
      wheelSensitivity: 0.2,
      autounselectify: false,
    };

    cyInstance = cytoscape(options);
    
    (cyInstance as any).compoundDragAndDrop({
        grabbedNode: (node: NodeSingular) => node.data('nodeType') !== 'plate',
        dropTarget: (node: NodeSingular) => node.data('nodeType') === 'plate',
        dropSibling: () => false,
        outThreshold: 50,
    });
    
    (cyInstance as any).gridGuide({ drawGrid: false, snapToGridOnRelease: true, snapToGridDuringDrag: true, gridSpacing: 20 });
    
    (cyInstance as any).contextMenus({
      menuItems: [
        {
          id: 'remove',
          content: 'Remove',
          selector: 'node, edge',
          onClickFunction: (evt: ContextMenuEvent) => {
            const targetElement = evt.target;
            targetElement.cy().container()?.dispatchEvent(
              new CustomEvent('cxt-remove', {
                detail: { elementId: targetElement.id() }
              })
            );
          }
        }
      ]
    });

    return cyInstance;
  };

  const destroyCytoscape = (cy: Core): void => {
    if (cy) {
      cy.destroy();
      cyInstance = null;
    }
  };

  const getCyInstance = (): Core | null => cyInstance;

  return { initCytoscape, destroyCytoscape, getCyInstance };
}
