import { ref, watch } from 'vue';
import type { Ref } from 'vue';
import type { GraphElement, GraphNode, GraphEdge, ValidationError, ModelData } from '../types';
import { getDistributionByName } from '../config/nodeDefinitions';

// A set of known BUGS functions to be ignored during validation of deterministic node equations.
const knownBugsFunctions = new Set([
  'sqrt', 'log', 'exp', 'sin', 'cos', 'tan', 'abs', 'round', 'trunc', 'step',
  'mean', 'sum', 'prod', 'sd', 'var', 'min', 'max', 'inverse', 'logdet',
  'logit', 'probit', 'cloglog', 'phi'
]);


/**
 * Composable for validating a BUGS graph model.
 * It produces a reactive map of errors without mutating the source elements.
 * @param elements - A ref containing the graph elements.
 * @param modelData - A ref containing the parsed model data and inits.
 */
export function useGraphValidator(
  elements: Ref<GraphElement[]>,
  modelData: Ref<ModelData>
) {
  const validationErrors = ref<Map<string, ValidationError[]>>(new Map());

  const validateGraph = () => {
    const newErrors = new Map<string, ValidationError[]>();
    const nodes = elements.value.filter(el => el.type === 'node') as GraphNode[];
    const edges = elements.value.filter(el => el.type === 'edge') as GraphEdge[];
    const nodeMap = new Map(nodes.map(n => [n.id, n]));
    const dataKeys = new Set(Object.keys(modelData.value.data));
    const nodeNames = new Set(nodes.map(n => n.name));

    nodes.forEach(node => {
      const errors: ValidationError[] = [];

      // Rule 1: Stochastic nodes must have the correct number of parents/parameters.
      if (node.nodeType === 'stochastic' || node.nodeType === 'observed') {
        const dist = getDistributionByName(node.distribution || '');
        if (dist && dist.paramCount !== undefined) {
          const parentEdges = edges.filter(e => e.target === node.id);
          let providedParams = parentEdges.length;
          
          const literalParams = Object.keys(node)
            .filter(key => key.startsWith('param') && node[key] && String(node[key]).trim() !== '')
            .map(key => node[key]);

          const linkedParams = literalParams.filter(p => nodeNames.has(p));
          const numericParams = literalParams.length - linkedParams.length;

          providedParams += numericParams;

          if (providedParams !== dist.paramCount) {
            errors.push({
              field: 'distribution',
              message: `Invalid number of inputs. ${dist.label} expects ${dist.paramCount}, but found ${providedParams}.`
            });
          }
        }
      }

      // Rule 2: Deterministic nodes validation
      if (node.nodeType === 'deterministic') {
        if (!node.equation?.trim()) {
            errors.push({
                field: 'equation',
                message: 'Deterministic node must have an equation.'
            });
        } else {
            const ancestorLoopVars = new Set<string>();
            let currentNode: GraphNode | undefined = node;
            while (currentNode?.parent) {
                const parentNode = nodeMap.get(currentNode.parent);
                if (parentNode && parentNode.nodeType === 'plate' && parentNode.loopVariable) {
                    ancestorLoopVars.add(parentNode.loopVariable);
                }
                currentNode = parentNode;
            }

            const variablesInEquation = new Set(node.equation.match(/[a-zA-Z_][a-zA-Z0-9_.]*/g) || []);
            const parentNames = new Set(
                edges
                    .filter(e => e.target === node.id)
                    .map(e => nodeMap.get(e.source)?.name)
                    .filter((name): name is string => !!name)
            );
            
            variablesInEquation.forEach(variable => {
                if (knownBugsFunctions.has(variable)) {
                    return;
                }
                const baseVariable = variable.split('[')[0];
                if (!parentNames.has(baseVariable) && !ancestorLoopVars.has(baseVariable)) {
                    errors.push({
                        field: 'equation',
                        message: `Variable '${baseVariable}' in equation is not a parent or an available loop index.`
                    });
                }
            });
        }
      }

      // Rule 3: Observed nodes must have a corresponding entry in the data section.
      if (node.observed && !dataKeys.has(node.name)) {
          errors.push({
              field: 'name',
              message: `Node is marked as observed, but no data found for '${node.name}'.`
          });
      }

      // Rule 4: Node name should be a valid variable name.
      const baseName = node.name.split('[')[0].trim();
      if (!/^[a-zA-Z][a-zA-Z0-9.]*$/.test(baseName)) {
          errors.push({
              field: 'name',
              message: `Base name '${baseName}' is not a valid BUGS variable name.`
          });
      }
      
      if (errors.length > 0) {
        newErrors.set(node.id, errors);
      }
    });

    validationErrors.value = newErrors;
  };

  watch([elements, modelData], validateGraph, { deep: true, immediate: true });

  return {
    validateGraph,
    validationErrors
  };
}
