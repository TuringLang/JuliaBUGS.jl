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
  initialValue?: string | number | boolean | null;
  indices?: string;
  loopVariable?: string;
  loopRange?: string;
  
  // Distribution parameters
  param1?: string;
  param2?: string;
  
  // Index signature to allow dynamic property access
  [key: string]: string | number | boolean | null | undefined | { x: number; y: number; } | string[];
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
  data: { [key: string]: string | number | boolean | null | undefined };
  inits: { [key: string]: string | number | boolean | null | undefined };
}


declare module 'cytoscape' {
  interface Core {
    svg(options?: Record<string, unknown>): string;
  }

  interface NodeSingular {
    data(key: string): unknown;
    data(): GraphNode;
  }

  interface EdgeSingular {
    data(): GraphEdge & { relationshipType?: 'stochastic' | 'deterministic' };
  }
}
