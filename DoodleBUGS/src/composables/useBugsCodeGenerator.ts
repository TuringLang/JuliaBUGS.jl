import { computed } from 'vue'
import type { Ref } from 'vue'
import { template } from 'lodash'
import bugsScriptRaw from '../templates/bugsScript.jl.tpl?raw'

const BUGS_SCRIPT_TEMPLATE = template(bugsScriptRaw)
import type { GraphElement, GraphNode, GraphEdge } from '../types'
import { buildTopologicalOrder } from '../utils/topoSort'

/**
 * Composable that generates BUGS model code from graph elements.
 * @param elements - A ref to the graph elements.
 */
export function useBugsCodeGenerator(elements: Ref<GraphElement[]>) {
  const generatedCode = computed(() => {
    const nodes = elements.value.filter((el) => el.type === 'node') as GraphNode[]
    const edges = elements.value.filter((el) => el.type === 'edge') as GraphEdge[]
    const nodeMap = new Map(nodes.map((n) => [n.id, n]))
    const nameToNode = new Map(nodes.map((n) => [n.name, n]))

    if (nodes.length === 0) {
      return 'model {\n  # Your model will appear here...\n}'
    }

    // Topological sort to determine node definition order.
    const sortedNodeIds = buildTopologicalOrder(nodes, edges)

    interface TreeMember {
      id: string
      type: 'node' | 'plate'
      children: TreeMember[]
    }
    const treeRoot: TreeMember = { id: 'root', type: 'plate', children: [] }
    const treeMemberMap = new Map<string, TreeMember>([['root', treeRoot]])

    nodes.forEach((node) => {
      treeMemberMap.set(node.id, {
        id: node.id,
        type: node.nodeType === 'plate' ? 'plate' : 'node',
        children: [],
      })
    })

    nodes.forEach((node) => {
      const parentId = node.parent || 'root'
      const parentMember = treeMemberMap.get(parentId)
      const childMember = treeMemberMap.get(node.id)
      if (parentMember && childMember) {
        parentMember.children.push(childMember)
      }
    })

    const formatParam = (raw: string): string => {
      const p = String(raw).trim()
      if (!p) return p
      // If already indexed (e.g., foo[i,j]) leave as-is
      if (/\[[^\]]+\]\s*$/.test(p)) return p
      // If numeric literal or contains parentheses (function/expression), leave as-is
      if (/^[+-]?(?:\d+\.?\d*|\d*\.\d+)(?:[eE][+-]?\d+)?$/.test(p) || /[()]/.test(p)) return p
      const ref = nameToNode.get(p)
      if (ref && ref.indices && String(ref.indices).trim() !== '') {
        return `${p}[${ref.indices}]`
      }
      return p
    }

    const generateCodeRecursive = (member: TreeMember, indentLevel: number): string[] => {
      const lines: string[] = []
      const indent = '  '.repeat(indentLevel)

      const sortedChildren = member.children.sort((a, b) => {
        // Plates first
        if (a.type === 'plate' && b.type !== 'plate') return -1
        if (b.type === 'plate' && a.type !== 'plate') return 1
        // Among nodes: observed/stochastic before deterministic
        const na = a.type === 'node' ? nodeMap.get(a.id) : undefined
        const nb = b.type === 'node' ? nodeMap.get(b.id) : undefined
        const pa = na ? (na.nodeType === 'deterministic' ? 1 : 0) : 0
        const pb = nb ? (nb.nodeType === 'deterministic' ? 1 : 0) : 0
        if (pa !== pb) return pa - pb
        // Tiebreaker: topological order
        return sortedNodeIds.indexOf(a.id) - sortedNodeIds.indexOf(b.id)
      })

      sortedChildren.forEach((child) => {
        const childNode = nodeMap.get(child.id)
        if (!childNode) return

        if (child.type === 'plate') {
          lines.push(`${indent}for (${childNode.loopVariable} in ${childNode.loopRange}) {`)
          lines.push(...generateCodeRecursive(child, indentLevel + 1))
          lines.push(`${indent}}`)
        } else {
          const nodeName = childNode.indices
            ? `${childNode.name}[${childNode.indices}]`
            : childNode.name

          if (childNode.nodeType === 'stochastic' || childNode.nodeType === 'observed') {
            const params = Object.keys(childNode)
              .filter(
                (key) =>
                  key.startsWith('param') &&
                  childNode[key as keyof GraphNode] &&
                  String(childNode[key as keyof GraphNode]).trim() !== ''
              )
              .map((key) => formatParam(String(childNode[key as keyof GraphNode])))
              .join(', ')

            // Hybrid: optional data-transform line before the stochastic line
            if (childNode.equation && String(childNode.equation).trim()) {
              lines.push(`${indent}${nodeName} <- ${childNode.equation}`)
            }

            let censorSuffix = ''
            const cl = childNode.censorLower ? String(childNode.censorLower).trim() : ''
            const cu = childNode.censorUpper ? String(childNode.censorUpper).trim() : ''
            if (cl || cu) {
              censorSuffix = `C(${cl},${cu ? ' ' + cu : ''})`
            }

            lines.push(`${indent}${nodeName} ~ ${childNode.distribution}(${params})${censorSuffix}`)
          } else if (childNode.nodeType === 'deterministic' && childNode.equation) {
            lines.push(`${indent}${nodeName} <- ${childNode.equation}`)
          }
        }
      })
      return lines
    }

    const finalCodeLines = generateCodeRecursive(treeRoot, 1)

    return ['model {', ...finalCodeLines, '}'].join('\n')
  })

  return {
    generatedCode,
  }
}

// Helpers to format JavaScript values as Julia literals for embedding
// Render a Julia NamedTuple field name.
// With replace_period=true (string-mode @bugs), the parser converts dots to underscores,
// so we must also use underscores in the data/inits NamedTuple keys to match.
function juliaFieldLiteral(name: string): string {
  const s = String(name).replace(/\./g, '_')
  // After dot→underscore the result is always a valid Julia identifier
  return s
}

function isScalarOrMissing(x: unknown): boolean {
  return x === null || x === undefined || typeof x === 'number'
}

function isVectorLike(v: unknown): v is (number | null)[] {
  return Array.isArray(v) && v.every(isScalarOrMissing)
}

function isMatrixLike(v: unknown): v is (number | null)[][] {
  if (!Array.isArray(v) || v.length === 0) return false
  const rows = v as unknown[]
  const firstRow = rows[0]
  if (!Array.isArray(firstRow)) return false
  const cols = (firstRow as unknown[]).length
  return rows.every(
    (r) =>
      Array.isArray(r) &&
      (r as unknown[]).length === cols &&
      (r as unknown[]).every(isScalarOrMissing)
  )
}

function formatNumber(n: number): string {
  if (Number.isNaN(n)) return 'NaN'
  if (!Number.isFinite(n)) return n > 0 ? 'Inf' : '-Inf'
  return `${n}`
}

function formatScalar(v: number | null | undefined): string {
  if (v === null || v === undefined) return 'missing'
  return formatNumber(v)
}

function formatVector(arr: (number | null)[]): string {
  return `[${arr.map(formatScalar).join(', ')}]`
}

function formatMatrix(mat: (number | null)[][]): string {
  const rows = mat.map((row) => row.map(formatScalar).join(' ')).join('\n        ')
  return `[\n        ${rows}\n    ]`
}

function formatValue(v: unknown): string {
  if (v === null) return 'missing'
  if (typeof v === 'number') return formatNumber(v)
  if (typeof v === 'boolean') return v ? 'true' : 'false'
  if (typeof v === 'string') return JSON.stringify(v)
  if (isMatrixLike(v)) return formatMatrix(v as (number | null)[][])
  if (isVectorLike(v)) return formatVector(v as (number | null)[])
  if (Array.isArray(v)) return `[${(v as unknown[]).map(formatValue).join(', ')}]`
  if (v && typeof v === 'object') return JSON.stringify(v)
  return 'nothing'
}

function buildNamedTupleLiteral(obj: Record<string, unknown>): string {
  const entries = Object.entries(obj).map(
    ([k, val]) => `  ${juliaFieldLiteral(k)} = ${formatValue(val)}`
  )
  if (!entries.length) return '()'
  const body = entries.join(',\n')
  const trailingComma = entries.length === 1 ? ',' : ''
  return `(\n${body}${trailingComma}\n)`
}

// Standalone script generator: builds a Julia script matching the backend's standalone template
export interface StandaloneGeneratorSettings {
  n_samples: number
  n_adapts: number
  n_chains: number
  seed?: number | null
}

export interface StandaloneScriptInput {
  modelCode: string
  data: Record<string, unknown>
  inits: Record<string, unknown>
  settings: StandaloneGeneratorSettings
}

export function generateStandaloneScript(input: StandaloneScriptInput): string {
  const { modelCode, data, inits, settings } = input

  const dataLiteral = buildNamedTupleLiteral(data as Record<string, unknown>)
  const initsLiteral = buildNamedTupleLiteral(inits as Record<string, unknown>)

  const nSamples = settings?.n_samples ?? 1000
  const nAdapts = settings?.n_adapts ?? 1000
  const nChains = settings?.n_chains ?? 1
  const seed = settings?.seed
  const seedLiteral =
    typeof seed === 'number' ? String(seed) : seed == null ? 'nothing' : JSON.stringify(seed)

  const hasCensoring = /\bC\(/.test(String(modelCode))

  return BUGS_SCRIPT_TEMPLATE({
    modelCode,
    dataLiteral,
    initsLiteral,
    nSamples,
    nAdapts,
    nChains,
    seedLiteral,
    hasCensoring,
  })
}
