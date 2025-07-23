export type NodeType = 'stochastic' | 'deterministic' | 'constant' | 'observed' | 'plate';

export type PaletteItemType = NodeType | 'add-edge';

export interface ValidationError {
  field: string;
  message: string;
}

// This interface is now a superset of all possible properties defined in nodeDefinitions.ts.
// All properties specific to a node type are optional.
export interface GraphNode {
  id: string;
  name: string;
  type: 'node';
  nodeType: NodeType;
  position: { x: number; y: number; };
  parent?: string;

  // Properties from definitions
  distribution?: string;
  equation?: string;
  observed?: boolean;
  initialValue?: any;
  indices?: string;
  loopVariable?: string;
  loopRange?: string;

  // Allows for other dynamic properties if needed in the future
  [key: string]: any;
}

export interface GraphEdge {
  id:string;
  name?: string;
  type: 'edge';
  source: string;
  target: string;
}

export type GraphElement = GraphNode | GraphEdge;

export interface ExampleModel {
  name: string;
  graphJSON: GraphElement[];
}

export interface ModelData {
  data: { [key: string]: any };
  inits: { [key: string]: any };
}


declare module 'cytoscape' {
  interface Core {
    panzoom(options?: any): any;
    svg(options?: any): string;
  }

  interface NodeSingular {
    data(key: string): any;
    data(): GraphNode;
  }

  interface EdgeSingular {
    data(): GraphEdge & { relationshipType?: 'stochastic' | 'deterministic' };
  }
}
