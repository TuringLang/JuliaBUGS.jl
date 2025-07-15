// src/config/nodeDefinitions.ts

import type { NodeType } from '../types';

/**
 * Defines the type of input control for a node property.
 */
export type NodePropertyType = 'select' | 'text' | 'number' | 'checkbox';

/**
 * Defines a single editable property for a node.
 */
export interface NodeProperty {
  key: string; // The key in the GraphNode object
  label: string;
  type: NodePropertyType;
  placeholder?: string;
  options?: { value: string; label: string }[]; // For 'select' type
  defaultValue: any;
  helpText?: string;
}

/**
 * Defines the entire schema for a specific type of node.
 */
export interface NodeDefinition {
  nodeType: NodeType;
  label: string; // User-facing label (e.g., in Palette)
  icon: string; // For the Palette
  description: string;
  styleClass: string;
  // All editable properties for this node type
  properties: NodeProperty[];
}

// A single place to define all available distributions
const distributionOptions = [
  { value: 'dnorm', label: 'Normal (dnorm)' },
  { value: 'dbeta', label: 'Beta (dbeta)' },
  { value: 'dgamma', label: 'Gamma (dgamma)' },
  { value: 'dbin', label: 'Binomial (dbin)' },
  { value: 'dpois', label: 'Poisson (dpois)' },
  { value: 'dt', label: 'Student-t (dt)' },
  { value: 'dchisqr', label: 'Chi-squared (dchisqr)' },
  { value: 'dweib', label: 'Weibull (dweib)' },
  { value: 'dexp', label: 'Exponential (dexp)' },
  { value: 'dloglik', label: 'Log-Likelihood (dloglik)' },
];

/**
 * The master list of all node definitions for the application.
 * This is the single source of truth.
 */
export const nodeDefinitions: NodeDefinition[] = [
  {
    nodeType: 'stochastic',
    label: 'Stochastic',
    icon: '~',
    description: 'Random variable with a distribution',
    styleClass: 'stochastic',
    properties: [
      { key: 'name', label: 'Name', type: 'text', defaultValue: 'StochasticNode' },
      { key: 'distribution', label: 'Distribution (~)', type: 'select', defaultValue: 'dnorm', options: distributionOptions },
      { key: 'observed', label: 'Observed', type: 'checkbox', defaultValue: false },
      { key: 'initialValue', label: 'Initial Value', type: 'text', placeholder: 'e.g., 0.5 or list(value=0.5)', defaultValue: '' },
      { key: 'indices', label: 'Indices', type: 'text', placeholder: 'e.g., i,j or 1:N', defaultValue: '', helpText: "Use comma-separated for multiple indices, e.g., 'i,j' or '1:N, 1:M'" },
    ]
  },
  {
    nodeType: 'deterministic',
    label: 'Deterministic',
    icon: '<-',
    description: 'Logical function of parents',
    styleClass: 'deterministic',
    properties: [
      { key: 'name', label: 'Name', type: 'text', defaultValue: 'DeterministicNode' },
      { key: 'equation', label: 'Equation (<--)', type: 'text', placeholder: 'e.g., a + b * x', defaultValue: '' },
      { key: 'indices', label: 'Indices', type: 'text', placeholder: 'e.g., i,j', defaultValue: '' },
    ]
  },
  {
    nodeType: 'constant',
    label: 'Constant',
    icon: 'C',
    description: 'A fixed value or parameter',
    styleClass: 'constant',
    properties: [
      { key: 'name', label: 'Name', type: 'text', defaultValue: 'ConstantNode' },
      { key: 'initialValue', label: 'Value', type: 'text', placeholder: 'e.g., 5 or 3.14', defaultValue: '0' },
      { key: 'indices', label: 'Indices', type: 'text', placeholder: 'e.g., i,j', defaultValue: '' },
    ]
  },
  {
    nodeType: 'observed',
    label: 'Observed',
    icon: 'O',
    description: 'A data node with a fixed value',
    styleClass: 'observed',
    properties: [
      { key: 'name', label: 'Name', type: 'text', defaultValue: 'ObservedNode' },
      { key: 'distribution', label: 'Distribution (~)', type: 'select', defaultValue: 'dnorm', options: distributionOptions },
      { key: 'observed', label: 'Observed', type: 'checkbox', defaultValue: true },
      { key: 'indices', label: 'Indices', type: 'text', placeholder: 'e.g., i,j or 1:N', defaultValue: '' },
    ]
  },
  {
    nodeType: 'plate',
    label: 'Plate',
    icon: '[]',
    description: 'Represents a loop structure',
    styleClass: 'plate',
    properties: [
      { key: 'name', label: 'Name', type: 'text', defaultValue: 'Plate' },
      { key: 'loopVariable', label: 'Loop Variable', type: 'text', placeholder: 'e.g., i', defaultValue: 'i' },
      { key: 'loopRange', label: 'Loop Range', type: 'text', placeholder: 'e.g., 1:N', defaultValue: '1:N', helpText: "Define the iteration for this plate, e.g., 'i' in '1:N'" },
    ]
  },
];

/**
 * A helper function to easily retrieve a node's definition by its type.
 * @param type The NodeType of the definition to find.
 * @returns The corresponding NodeDefinition or undefined if not found.
 */
export const getNodeDefinition = (type: NodeType): NodeDefinition | undefined => {
  return nodeDefinitions.find(def => def.nodeType === type);
};

/**
 * A helper function to get the default data object for a new node.
 * @param type The NodeType for which to get default data.
 * @returns An object with all the default properties for that node type.
 */
export const getDefaultNodeData = (type: NodeType): { [key: string]: any } => {
  const definition = getNodeDefinition(type);
  if (!definition) {
    return {};
  }
  const defaultData: { [key: string]: any } = {};
  definition.properties.forEach(prop => {
    defaultData[prop.key] = prop.defaultValue;
  });
  return defaultData;
};
