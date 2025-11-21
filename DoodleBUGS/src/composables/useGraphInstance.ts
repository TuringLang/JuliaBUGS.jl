import cytoscape from 'cytoscape';
import type { Core, ElementDefinition, NodeSingular } from 'cytoscape';
// NOTE: gridGuide and contextMenus extensions are DISABLED for iOS/iPad/WebKit compatibility
// They block touch events and prevent node/edge creation on mobile devices
// import gridGuide from 'cytoscape-grid-guide';
// import contextMenus from 'cytoscape-context-menus';
import dagre from 'cytoscape-dagre';
import fcose from 'cytoscape-fcose';
import cola from 'cytoscape-cola';
import klay from 'cytoscape-klay';
import undoRedo from 'cytoscape-undo-redo';
import { useCompoundDragDrop } from './useCompoundDragDrop';
import svg from 'cytoscape-svg';

// NOTE: Do NOT register gridGuide or contextMenus - they break iPad/mobile touch events
cytoscape.use(dagre);
cytoscape.use(fcose);
cytoscape.use(cola);
cytoscape.use(klay);
cytoscape.use(svg);
cytoscape.use(undoRedo);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UndoRedoInstance = any;

let cyInstance: Core | null = null;
let urInstance: UndoRedoInstance = null;

export function useGraphInstance() {
  const initCytoscape = (container: HTMLElement, initialElements: ElementDefinition[]): Core => {
    if (cyInstance) {
      cyInstance.destroy();
      cyInstance = null;
      urInstance = null;
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
              const name = ele.data('name') as string;
              const indices = ele.data('indices') as string | undefined;
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
        {
          selector: '.cdnd-drag-out',
          style: { 'border-color': '#e74c3c', 'border-style': 'dashed', 'border-width': 2, 'overlay-color': '#e74c3c', 'overlay-opacity': 0.3, 'overlay-padding': 5 }
        },
        {
          selector: '.cdnd-grabbed-node.cdnd-drag-out',
          style: { 'border-color': '#e74c3c', 'border-style': 'dashed', 'border-width': 2, 'background-color': '#f1c40f', 'opacity': 0.7, 'overlay-color': '#e74c3c', 'overlay-opacity': 0.3, 'overlay-padding': 5 }
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

    // Initialize undo-redo
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    urInstance = (cyInstance as any).undoRedo({
      isDebug: false,
      undoableDrag: true,
      stackSizeLimit: 50,
    });

    urInstance.action("move", 
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      function(args: any) {
        const eles = typeof args.eles === "string" ? cyInstance!.$(args.eles) : args.eles;
        const nodes = eles.nodes();
        const edges = eles.edges();
        
        const oldNodesParents: (string | null)[] = [];
        const oldEdgesSources: string[] = [];
        const oldEdgesTargets: string[] = [];
        
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        nodes.forEach((node: any) => {
          oldNodesParents.push(node.parent().length > 0 ? node.parent().id() : null);
        });
        
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        edges.forEach((edge: any) => {
          oldEdgesSources.push(edge.source().id());
          oldEdgesTargets.push(edge.target().id());
        });
        
        return {
            oldNodesParents: oldNodesParents,
            newNodes: nodes.move(args.location),
            oldEdgesSources: oldEdgesSources,
            oldEdgesTargets: oldEdgesTargets,
            newEdges: edges.move(args.location)
        };
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      function(eles: any) {
        let newEles = cyInstance!.collection();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const location: any = {};
        
        if (eles.newNodes.length > 0) {
            const parent = eles.newNodes[0].parent();
            location.parent = parent.length > 0 ? parent.id() : null;

            for (let i = 0; i < eles.newNodes.length; i++) {
                const newNode = eles.newNodes[i].move({
                    parent: eles.oldNodesParents[i]
                });
                newEles = newEles.union(newNode);
            }
        } else if (eles.newEdges.length > 0) {
            location.source = eles.newEdges[0].source().id();
            location.target = eles.newEdges[0].target().id();

            for (let i = 0; i < eles.newEdges.length; i++) {
                const newEdge = eles.newEdges[i].move({
                    source: eles.oldEdgesSources[i],
                    target: eles.oldEdgesTargets[i]
                });
                newEles = newEles.union(newEdge);
            }
        }
        return {
            eles: newEles,
            location: location
        };
      }
    );

    // Initialize custom compound drag and drop
    useCompoundDragDrop(cyInstance, {
      grabbedNode: (node: NodeSingular) => node !== undefined, // Allow dragging all node types
      dropTarget: (node: NodeSingular) => node.data('nodeType') === 'plate',
      dropSibling: () => false,
      outThreshold: 30, // Reduced threshold for better UX
    }, urInstance);

    // NOTE: gridGuide and contextMenus extensions are disabled
    // These extensions interfere with touch events on iOS/Safari/WebKit browsers
    // Uncomment below to re-enable for desktop-only usage:
    /*
    (cyInstance as Core & { gridGuide: (options: { drawGrid: boolean; snapToGridOnRelease: boolean; snapToGridDuringDrag: boolean; gridSpacing: number }) => void }).gridGuide({ drawGrid: false, snapToGridOnRelease: true, snapToGridDuringDrag: true, gridSpacing: 20 });

    (cyInstance as Core & { contextMenus: (options: { menuItems: { id: string; content: string; selector: string; onClickFunction: (evt: cytoscape.EventObject) => void }[] }) => void }).contextMenus({
      menuItems: [
        {
          id: 'remove',
          content: 'Remove',
          selector: 'node, edge',
          onClickFunction: (evt: cytoscape.EventObject) => {
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
    */

    return cyInstance;
  };

  const destroyCytoscape = (cy: Core): void => {
    if (cy) {
      cy.destroy();
      cyInstance = null;
      urInstance = null;
    }
  };

  const getCyInstance = (): Core | null => cyInstance;
  const getUndoRedoInstance = (): UndoRedoInstance => urInstance;

  return { initCytoscape, destroyCytoscape, getCyInstance, getUndoRedoInstance };
}
