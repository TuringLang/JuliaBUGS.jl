import { computed } from 'vue';
import type { Ref } from 'vue';
import type { GraphElement, GraphNode, GraphEdge } from '../types';

/**
 * Composable that generates BUGS model code from graph elements.
 * @param elements - A ref to the graph elements.
 */
export function useBugsCodeGenerator(elements: Ref<GraphElement[]>) {
  const generatedCode = computed(() => {
    const nodes = elements.value.filter(el => el.type === 'node') as GraphNode[];
    const edges = elements.value.filter(el => el.type === 'edge') as GraphEdge[];
    const nodeMap = new Map(nodes.map(n => [n.id, n]));
    const nameToNode = new Map(nodes.map(n => [n.name, n]));

    if (nodes.length === 0) {
      return 'model {\n  # Your model will appear here...\n}';
    }

    // Topological Sort (Kahn's algorithm) to determine node definition order.
    const nodeInDegree: { [key: string]: number } = {};
    const adjacencyList: { [key: string]: string[] } = {};
    nodes.forEach(node => {
      nodeInDegree[node.id] = 0;
      adjacencyList[node.id] = [];
    });
    edges.forEach(edge => {
      if (adjacencyList[edge.source] && nodeInDegree[edge.target] !== undefined) {
        adjacencyList[edge.source].push(edge.target);
        nodeInDegree[edge.target]++;
      }
    });
    const queue = nodes.filter(node => nodeInDegree[node.id] === 0).map(n => n.id);
    const sortedNodeIds: string[] = [];
    while (queue.length > 0) {
      const currentNodeId = queue.shift()!;
      sortedNodeIds.push(currentNodeId);
      adjacencyList[currentNodeId]?.forEach(childNodeId => {
        if (nodeInDegree[childNodeId] !== undefined) {
          nodeInDegree[childNodeId]--;
          if (nodeInDegree[childNodeId] === 0) {
            queue.push(childNodeId);
          }
        }
      });
    }

    interface TreeMember {
      id: string;
      type: 'node' | 'plate';
      children: TreeMember[];
    }
    const treeRoot: TreeMember = { id: 'root', type: 'plate', children: [] };
    const treeMemberMap = new Map<string, TreeMember>([['root', treeRoot]]);

    nodes.forEach(node => {
      treeMemberMap.set(node.id, { id: node.id, type: node.nodeType === 'plate' ? 'plate' : 'node', children: [] });
    });

    nodes.forEach(node => {
      const parentId = node.parent || 'root';
      const parentMember = treeMemberMap.get(parentId);
      const childMember = treeMemberMap.get(node.id);
      if (parentMember && childMember) {
        parentMember.children.push(childMember);
      }
    });

    const formatParam = (raw: string): string => {
      const p = String(raw).trim();
      if (!p) return p;
      // If already indexed (e.g., foo[i,j]) leave as-is
      if (/\[[^\]]+\]\s*$/.test(p)) return p;
      // If numeric literal or contains parentheses (function/expression), leave as-is
      if (/^[+-]?(?:\d+\.?\d*|\d*\.\d+)(?:[eE][+-]?\d+)?$/.test(p) || /[()]/.test(p)) return p;
      const ref = nameToNode.get(p);
      if (ref && ref.indices && String(ref.indices).trim() !== '') {
        return `${p}[${ref.indices}]`;
      }
      return p;
    };

    const generateCodeRecursive = (member: TreeMember, indentLevel: number): string[] => {
      const lines: string[] = [];
      const indent = '  '.repeat(indentLevel);

      const sortedChildren = member.children.sort((a, b) => {
        // Plates first
        if (a.type === 'plate' && b.type !== 'plate') return -1;
        if (b.type === 'plate' && a.type !== 'plate') return 1;
        // Among nodes: observed/stochastic before deterministic
        const na = a.type === 'node' ? nodeMap.get(a.id) : undefined;
        const nb = b.type === 'node' ? nodeMap.get(b.id) : undefined;
        const pa = na ? (na.nodeType === 'deterministic' ? 1 : 0) : 0;
        const pb = nb ? (nb.nodeType === 'deterministic' ? 1 : 0) : 0;
        if (pa !== pb) return pa - pb;
        // Tiebreaker: topological order
        return sortedNodeIds.indexOf(a.id) - sortedNodeIds.indexOf(b.id);
      });

      sortedChildren.forEach(child => {
        const childNode = nodeMap.get(child.id);
        if (!childNode) return;

        if (child.type === 'plate') {
          lines.push(`${indent}for (${childNode.loopVariable} in ${childNode.loopRange}) {`);
          lines.push(...generateCodeRecursive(child, indentLevel + 1));
          lines.push(`${indent}}`);
        } else {
          const nodeName = childNode.indices ? `${childNode.name}[${childNode.indices}]` : childNode.name;

          if (childNode.nodeType === 'stochastic' || childNode.nodeType === 'observed') {
            const params = Object.keys(childNode)
              .filter(key => key.startsWith('param') && childNode[key as keyof GraphNode] && String(childNode[key as keyof GraphNode]).trim() !== '')
              .map(key => formatParam(String(childNode[key as keyof GraphNode])))
              .join(', ');
            lines.push(`${indent}${nodeName} ~ ${childNode.distribution}(${params})`);
          } else if (childNode.nodeType === 'deterministic' && childNode.equation) {
            lines.push(`${indent}${nodeName} <- ${childNode.equation}`);
          }
        }
      });
      return lines;
    };

    const finalCodeLines = generateCodeRecursive(treeRoot, 1);

    return ['model {', ...finalCodeLines, '}'].join('\n');
  });

  return {
    generatedCode,
  };
}

// Helpers to format JavaScript values as Julia literals for embedding
// Render a Julia NamedTuple field name: either bare identifier or var"..."
function juliaFieldLiteral(name: string): string {
  const s = String(name);
  const idok = /^[A-Za-z_][A-Za-z0-9_]*$/.test(s);
  if (idok) return s;
  const escaped = s.replace(/"/g, '\\"');
  return `var"${escaped}"`;
}

function isVectorOfNumbers(v: unknown): v is number[] {
  return Array.isArray(v) && v.every(x => typeof x === 'number');
}

function isMatrixLike(v: unknown): v is number[][] {
  if (!Array.isArray(v) || v.length === 0) return false;
  const rows = v as unknown[];
  const firstRow = rows[0];
  if (!Array.isArray(firstRow)) return false;
  const cols = (firstRow as unknown[]).length;
  return rows.every(r => Array.isArray(r)
    && (r as unknown[]).length === cols
    && (r as unknown[]).every(x => typeof x === 'number'));
}

function formatNumber(n: number): string {
  if (Number.isNaN(n)) return 'NaN';
  if (!Number.isFinite(n)) return n > 0 ? 'Inf' : '-Inf';
  return `${n}`;
}

function formatVector(arr: number[]): string {
  return `[${arr.map(formatNumber).join(', ')}]`;
}

function formatMatrix(mat: number[][]): string {
  const rows = mat.map(row => row.map(formatNumber).join(' ')).join('\n        ');
  return `[\n        ${rows}\n    ]`;
}

function formatValue(v: unknown): string {
  if (v === null) return 'missing';
  if (typeof v === 'number') return formatNumber(v);
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'string') return JSON.stringify(v);
  if (isMatrixLike(v)) return formatMatrix(v as number[][]);
  if (isVectorOfNumbers(v)) return formatVector(v as number[]);
  if (Array.isArray(v)) return JSON.stringify(v);
  if (v && typeof v === 'object') return JSON.stringify(v);
  return 'nothing';
}

function buildNamedTupleLiteral(obj: Record<string, unknown>): string {
  const entries = Object.entries(obj).map(([k, val]) => `  ${juliaFieldLiteral(k)} = ${formatValue(val)}`);
  return entries.length ? `(\n${entries.join(',\n')}\n)` : '()';
}

// Standalone script generator: builds a Julia script matching the backend's standalone template
export interface StandaloneGeneratorSettings {
  n_samples: number;
  n_adapts: number;
  n_chains: number;
  seed?: number | null;
}

export interface StandaloneScriptInput {
  modelCode: string;
  data: Record<string, unknown>;
  inits: Record<string, unknown>;
  settings: StandaloneGeneratorSettings;
}

export function generateStandaloneScript(input: StandaloneScriptInput): string {
  const { modelCode, data, inits, settings } = input;

  // Build literal NamedTuples
  const dataLiteral = buildNamedTupleLiteral(data as Record<string, unknown>);
  const initsLiteral = buildNamedTupleLiteral(inits as Record<string, unknown>);

  const nSamples = settings?.n_samples ?? 1000;
  const nAdapts = settings?.n_adapts ?? 1000;
  const nChains = settings?.n_chains ?? 1;
  const seed = settings?.seed;
  const seedLiteral = typeof seed === 'number' ? String(seed) : (seed == null ? 'nothing' : JSON.stringify(seed));

  const script = `using JuliaBUGS, AbstractMCMC, AdvancedHMC, LogDensityProblems, LogDensityProblemsAD, MCMCChains, ReverseDiff, Random

data = ${dataLiteral}

inits = ${initsLiteral}

# Model definition using a string literal
model_def = JuliaBUGS.@bugs("""
${String(modelCode)}
""", true, false)

# Compile the model
model = JuliaBUGS.compile(model_def, data, inits)

# Wrap the model for automatic differentiation with ReverseDiff
ad_model = ADgradient(:ReverseDiff, model)
ld_model = AbstractMCMC.LogDensityModel(ad_model)

# Define sampling parameters
n_samples, n_adapts = ${nSamples}, ${nAdapts}
n_chains = ${nChains}
seed = ${seedLiteral}

seed_val = tryparse(Int, string(seed))
rng = seed === nothing ? Random.MersenneTwister() : (seed_val === nothing ? Random.MersenneTwister() : Random.MersenneTwister(seed_val))

D = LogDensityProblems.dimension(ad_model); initial_θ = rand(rng, D)

# Sample the model using AbstractMCMC
if n_chains > 1 && Threads.nthreads() > 1
    chain = AbstractMCMC.sample(
        rng,
        ld_model,
        AdvancedHMC.NUTS(0.8),
        AbstractMCMC.MCMCThreads(),
        n_samples,
        n_chains;
        chain_type = Chains,
        n_adapts = n_adapts,
        init_params = initial_θ,
        discard_initial = n_adapts,
        progress = false,
    )
elseif n_chains > 1
    chain = AbstractMCMC.sample(
        rng,
        ld_model,
        AdvancedHMC.NUTS(0.8),
        AbstractMCMC.MCMCSerial(),
        n_samples,
        n_chains;
        chain_type = Chains,
        n_adapts = n_adapts,
        init_params = initial_θ,
        discard_initial = n_adapts,
        progress = false,
    )
else
    chain = AbstractMCMC.sample(
        rng,
        ld_model,
        AdvancedHMC.NUTS(0.8),
        n_samples;
        chain_type = Chains,
        n_adapts = n_adapts,
        init_params = initial_θ,
        discard_initial = n_adapts,
        progress = false,
    )
end

describe(chain)
`;

  return script;
}
