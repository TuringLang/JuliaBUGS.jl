import type { NodeType, ExampleModel } from '../types';

export type NodePropertyType = 'select' | 'text' | 'number' | 'checkbox';

export interface SelectOption {
    value: string;
    label: string;
    paramCount?: number;
    paramNames?: string[];
    helpText?: string;
}

export interface NodeProperty {
    key: string;
    label: string;
    type: NodePropertyType;
    placeholder?: string;
    options?: SelectOption[];
    defaultValue: any;
    helpText?: string;
}

export interface NodeDefinition {
    nodeType: NodeType;
    label: string;
    icon: string;
    description: string;
    styleClass: string;
    properties: NodeProperty[];
    parameters?: NodeProperty[]; // Optional parameters for distributions
}

const distributionOptions: SelectOption[] = [
    { value: 'dnorm', label: 'Normal (dnorm)', paramCount: 2, paramNames: ['mean', 'precision'], helpText: 'Parameters: mean (expected value), precision (1/variance). Note: BUGS uses precision instead of standard deviation.' },
    { value: 'dgamma', label: 'Gamma (dgamma)', paramCount: 2, paramNames: ['shape', 'rate'], helpText: 'Parameters: shape (alpha), rate (1/beta).' },
    { value: 'dbeta', label: 'Beta (dbeta)', paramCount: 2, paramNames: ['shape1', 'shape2'], helpText: 'Parameters: shape1 (alpha), shape2 (beta).' },
    { value: 'dbin', label: 'Binomial (dbin)', paramCount: 2, paramNames: ['prob', 'size'], helpText: 'Parameters: prob (success probability), size (number of trials).' },
    { value: 'dpois', label: 'Poisson (dpois)', paramCount: 1, paramNames: ['lambda'], helpText: 'Parameter: lambda (expected number of occurrences).' },
    { value: 'dt', label: 'Student-t (dt)', paramCount: 3, paramNames: ['mu', 'tau', 'k'], helpText: 'Parameters: mu (mean), tau (precision), k (degrees of freedom).' },
    { value: 'dunif', label: 'Uniform (dunif)', paramCount: 2, paramNames: ['lower', 'upper'], helpText: 'Parameters: lower (minimum value), upper (maximum value).' },
];

export const nodeDefinitions: NodeDefinition[] = [
    {
        nodeType: 'stochastic',
        label: 'Stochastic',
        icon: '~',
        description: 'Random variable with a distribution',
        styleClass: 'stochastic',
        properties: [
            { key: 'name', label: 'Name', type: 'text', defaultValue: 'stochastic.node' },
            { key: 'distribution', label: 'Distribution (~)', type: 'select', defaultValue: 'dnorm', options: distributionOptions },
            { key: 'observed', label: 'Observed', type: 'checkbox', defaultValue: false, helpText: "If checked, this node's value is provided in the data section." },
            { key: 'indices', label: 'Indices', type: 'text', placeholder: 'e.g., i,j or 1:N', defaultValue: '' },
        ],
        parameters: [ // These fields will be used to store literal values or parent node links
            { key: 'param1', label: 'Parameter 1', type: 'text', defaultValue: '' },
            { key: 'param2', label: 'Parameter 2', type: 'text', defaultValue: '' },
            { key: 'param3', label: 'Parameter 3', type: 'text', defaultValue: '' },
        ]
    },
    {
        nodeType: 'deterministic',
        label: 'Deterministic',
        icon: '<-',
        description: 'Logical function of parents',
        styleClass: 'deterministic',
        properties: [
            { key: 'name', label: 'Name', type: 'text', defaultValue: 'logical.node' },
            { key: 'equation', label: 'Equation (<-)', type: 'text', placeholder: 'e.g., a + b * x', defaultValue: '' },
            { key: 'indices', label: 'Indices', type: 'text', placeholder: 'e.g., i,j', defaultValue: '' },
        ]
    },
    {
        nodeType: 'constant',
        label: 'Constant',
        icon: 'C',
        description: 'A fixed value or data input',
        styleClass: 'constant',
        properties: [
            { key: 'name', label: 'Name', type: 'text', defaultValue: 'constant.node' },
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
            { key: 'name', label: 'Name', type: 'text', defaultValue: 'observed.node' },
            { key: 'distribution', label: 'Distribution (~)', type: 'select', defaultValue: 'dnorm', options: distributionOptions },
            { key: 'observed', label: 'Observed', type: 'checkbox', defaultValue: true },
            { key: 'indices', label: 'Indices', type: 'text', placeholder: 'e.g., i,j or 1:N', defaultValue: '' },
        ],
        parameters: [
            { key: 'param1', label: 'Parameter 1', type: 'text', defaultValue: '' },
            { key: 'param2', label: 'Parameter 2', type: 'text', defaultValue: '' },
            { key: 'param3', label: 'Parameter 3', type: 'text', defaultValue: '' },
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
            { key: 'loopRange', label: 'Loop Range', type: 'text', placeholder: 'e.g., 1:N', defaultValue: '1:N' },
        ]
    },
];

export const connectionPaletteItems: { label: string; type: 'add-edge'; styleClass: string; description: string }[] = [
  { label: 'Add Edge', type: 'add-edge', styleClass: 'connection', description: 'Connect two nodes' },
];

export const exampleModels: { name: string; key: string }[] = [
    { name: 'Rats Model', key: 'rats' },
];

export const getNodeDefinition = (type: NodeType): NodeDefinition | undefined => {
    return nodeDefinitions.find(def => def.nodeType === type);
};

export const getDistributionByName = (distName: string): SelectOption | undefined => {
    return distributionOptions.find(opt => opt.value === distName);
};

export const getDefaultNodeData = (type: NodeType): { [key: string]: any } => {
    const definition = getNodeDefinition(type);
    if (!definition) return {};
    
    const defaultData: { [key: string]: any } = {};
    definition.properties.forEach(prop => {
        defaultData[prop.key] = prop.defaultValue;
    });
    if (definition.parameters) {
        definition.parameters.forEach(param => {
            defaultData[param.key] = param.defaultValue;
        });
    }
    return defaultData;
};
