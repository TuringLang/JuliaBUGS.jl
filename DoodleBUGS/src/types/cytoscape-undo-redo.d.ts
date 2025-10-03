declare module 'cytoscape-undo-redo' {
  import { Core } from 'cytoscape';

  interface UndoRedoOptions {
    isDebug?: boolean;
    actions?: {
      [key: string]: {
        undo: (arg: any) => any;
        redo: (arg: any) => any;
      };
    };
    undoableDrag?: boolean;
    stackSizeLimit?: number;
    ready?: () => void;
  }

  interface UndoRedoInstance {
    do: (actionName: string, args: any) => any;
    undo: () => boolean;
    redo: () => boolean;
    reset: () => void;
    isUndoStackEmpty: () => boolean;
    isRedoStackEmpty: () => boolean;
    getUndoStackSize: () => number;
    getRedoStackSize: () => number;
  }

  function undoRedo(options?: UndoRedoOptions): (cy: Core) => UndoRedoInstance;

  export = undoRedo;
}