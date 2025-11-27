import cytoscape from 'cytoscape';
import type { Core, ElementDefinition, NodeSingular, EdgeSingular } from 'cytoscape';
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
import { useUiStore } from '../stores/uiStore';

// NOTE: Do NOT register gridGuide or contextMenus - they break iPad/mobile touch events
cytoscape.use(dagre);
cytoscape.use(fcose);
cytoscape.use(cola);
cytoscape.use(klay);
cytoscape.use(svg);
cytoscape.use(undoRedo);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UndoRedoInstance = any;

const instances = new Map<string, { cy: Core, ur: UndoRedoInstance }>();

export function useGraphInstance() {
  const uiStore = useUiStore();

  const initCytoscape = (container: HTMLElement, initialElements: ElementDefinition[], graphId: string): Core => {
    if (instances.has(graphId)) {
      const instance = instances.get(graphId)!;
      instance.cy.destroy();
      instances.delete(graphId);
    }

    const options: cytoscape.CytoscapeOptions = {
      container: container,
      elements: initialElements,
      style: [
        {
          selector: 'node',
          style: {
            // Core shape and size logic: Use global preference from uiStore
            'background-color': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.backgroundColor || '#999',
            'background-opacity': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.backgroundOpacity ?? 1,
            'border-color': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.borderColor || '#555',
            'border-width': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.borderWidth || 2,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            'border-style': (ele: NodeSingular) => (uiStore.nodeStyles[ele.data('nodeType')]?.borderStyle || 'solid') as any,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            'shape': (ele: NodeSingular) => (uiStore.nodeStyles[ele.data('nodeType')]?.shape || 'ellipse') as any,
            'width': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.width || 60,
            'height': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.height || 60,
            
            'label': (ele: NodeSingular) => {
              const name = ele.data('name') as string;
              const indices = ele.data('indices') as string | undefined;
              return indices ? `${name}[${indices}]` : name;
            },
            'color': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.labelColor || '#000000',
             
            'font-size': (ele: NodeSingular) => uiStore.nodeStyles[ele.data('nodeType')]?.labelFontSize || 10,
            
            'text-valign': 'center', 'text-halign': 'center', 'padding': '10px',
            'text-wrap': 'wrap', 'text-max-width': '80px', 
            'line-height': 1.2, 'z-index': 10
          },
        },
        {
          selector: 'node[nodeType="plate"]',
          style: {
            // Plate specific overrides - label handling primarily
            'label': (ele: NodeSingular) => `for(${ele.data('loopVariable')} in ${ele.data('loopRange')})`,
          },
        },
        {
          selector: ':parent',
          style: { 'text-valign': 'top', 'text-halign': 'center', 'padding': '15px', 'z-index': 5 },
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
            'font-size': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelFontSize || 8,
            'color': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelColor || '#000000',
            
            'text-rotation': 'autorotate',
            'text-background-opacity': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelBackgroundOpacity ?? 1,
            'text-background-color': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelBackgroundColor || '#ffffff',
            'text-background-padding': '3px',
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            'text-background-shape': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelBackgroundShape || 'rectangle' as any,
            
            'text-border-width': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelBorderWidth ?? 1,
            'text-border-color': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelBorderColor || '#ccc',
            'text-border-opacity': (ele: EdgeSingular) => uiStore.edgeStyles[ele.data('relationshipType') as 'stochastic'|'deterministic']?.labelBackgroundOpacity ?? 1,
          }
        },
        {
          selector: 'edge[relationshipType="stochastic"]',
          style: {
            'line-color': () => uiStore.edgeStyles.stochastic.color,
            'target-arrow-color': () => uiStore.edgeStyles.stochastic.color,
            'width': () => uiStore.edgeStyles.stochastic.width,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            'line-style': () => uiStore.edgeStyles.stochastic.lineStyle as any,
          },
        },
        {
          selector: 'edge[relationshipType="deterministic"]',
          style: {
            'line-color': () => uiStore.edgeStyles.deterministic.color,
            'target-arrow-color': () => uiStore.edgeStyles.deterministic.color,
            'width': () => uiStore.edgeStyles.deterministic.width,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            'line-style': () => uiStore.edgeStyles.deterministic.lineStyle as any,
          },
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
      maxZoom: 7,
      boxSelectionEnabled: true,
      autounselectify: false,
    };

    const cyInstance = cytoscape(options);

    // Initialize undo-redo
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const urInstance = (cyInstance as any).undoRedo({
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

    instances.set(graphId, { cy: cyInstance, ur: urInstance });

    return cyInstance;
  };

  const destroyCytoscape = (graphId: string): void => {
    if (instances.has(graphId)) {
      const instance = instances.get(graphId)!;
      instance.cy.destroy();
      instances.delete(graphId);
    }
  };

  const getCyInstance = (graphId: string): Core | null => {
    return instances.get(graphId)?.cy || null;
  };

  const getUndoRedoInstance = (graphId: string): UndoRedoInstance => {
    return instances.get(graphId)?.ur || null;
  };

  return { initCytoscape, destroyCytoscape, getCyInstance, getUndoRedoInstance };
}
