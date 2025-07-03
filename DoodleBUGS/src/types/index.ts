export type NodeType = 'stochastic' | 'deterministic' | 'constant' | 'observed' | 'plate';

export type PaletteItemType = NodeType | 'add-edge';

export interface GraphNode {
  id: string;
  name: string;
  type: 'node';
  nodeType: NodeType;
  position: { x: number; y: number; };
  parent?: string;
  distribution?: string;
  equation?: string;
  observed?: boolean;
  initialValue?: any;
  indices?: string;
  loopVariable?: string;
  loopRange?: string;
}

export interface GraphEdge {
  id: string;
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

declare module 'cytoscape' {
  interface Core {
    panzoom(options?: any): any;
  }

  interface NodeSingular {
    data(key: string): any;
    data(): GraphNode;
  }

  interface EdgeSingular {
    data(): GraphEdge & { relationshipType?: 'stochastic' | 'deterministic' };
  }
}
