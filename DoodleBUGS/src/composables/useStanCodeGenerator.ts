import { computed } from 'vue'
import type { Ref } from 'vue'
import type { GraphElement, GraphNode, GraphEdge } from '../types'

interface DistributionMapping {
  stanName: string
  transformParams: (params: string[], node: GraphNode) => string[]
  stanParamNames: string[]
  needsPrecisionConvert?: boolean
  swapArgs?: boolean
}

const DISTRIBUTION_MAP: Record<string, DistributionMapping> = {
  dnorm: {
    stanName: 'normal',
    stanParamNames: ['mu', 'sigma'],
    needsPrecisionConvert: true,
    transformParams: (params) => {
      const [mu, tau] = params
      return [mu || '0', tau ? `1.0 / sqrt(${tau})` : '1']
    },
  },
  dgamma: {
    stanName: 'gamma',
    stanParamNames: ['alpha', 'beta'],
    transformParams: (params) => [params[0] || '0.001', params[1] || '0.001'],
  },
  dbeta: {
    stanName: 'beta',
    stanParamNames: ['alpha', 'beta'],
    transformParams: (params) => [params[0] || '1', params[1] || '1'],
  },
  dbern: {
    stanName: 'bernoulli',
    stanParamNames: ['theta'],
    transformParams: (params) => [params[0] || '0.5'],
  },
  dbin: {
    stanName: 'binomial',
    stanParamNames: ['N', 'theta'],
    swapArgs: true,
    transformParams: (params) => {
      const [prob, size] = params
      return [size || '1', prob || '0.5']
    },
  },
  dpois: {
    stanName: 'poisson',
    stanParamNames: ['lambda'],
    transformParams: (params) => [params[0] || '1'],
  },
  dexp: {
    stanName: 'exponential',
    stanParamNames: ['lambda'],
    transformParams: (params) => [params[0] || '1'],
  },
  dt: {
    stanName: 'student_t',
    stanParamNames: ['nu', 'mu', 'sigma'],
    needsPrecisionConvert: true,
    transformParams: (params) => {
      const [mu, tau, k] = params
      return [k || '1', mu || '0', tau ? `1.0 / sqrt(${tau})` : '1']
    },
  },
  dunif: {
    stanName: 'uniform',
    stanParamNames: ['alpha', 'beta'],
    transformParams: (params) => [params[0] || '0', params[1] || '1'],
  },
  dcat: {
    stanName: 'categorical',
    stanParamNames: ['theta'],
    transformParams: (params) => [params[0] || 'theta'],
  },
  dmnorm: {
    stanName: 'multi_normal_prec',
    stanParamNames: ['mu', 'Omega'],
    transformParams: (params) => [params[0] || 'mu', params[1] || 'Omega'],
  },
  dwish: {
    stanName: 'wishart',
    stanParamNames: ['nu', 'S'],
    transformParams: (params) => {
      const [R, k] = params
      return [k || '1', R ? `inverse(${R})` : 'S']
    },
  },
  ddirich: {
    stanName: 'dirichlet',
    stanParamNames: ['alpha'],
    transformParams: (params) => [params[0] || 'alpha'],
  },
  dmulti: {
    stanName: 'multinomial',
    stanParamNames: ['theta'],
    transformParams: (params) => [params[0] || 'theta'],
  },
  dlnorm: {
    stanName: 'lognormal',
    stanParamNames: ['mu', 'sigma'],
    needsPrecisionConvert: true,
    transformParams: (params) => {
      const [mu, tau] = params
      return [mu || '0', tau ? `1.0 / sqrt(${tau})` : '1']
    },
  },
  dweib: {
    stanName: 'weibull',
    stanParamNames: ['alpha', 'sigma'],
    transformParams: (params) => {
      const [a, b] = params
      return [a || '1', b ? `1.0 / ${b}` : '1']
    },
  },
  dchisqr: {
    stanName: 'chi_square',
    stanParamNames: ['nu'],
    transformParams: (params) => [params[0] || '1'],
  },
  dnegbin: {
    stanName: 'neg_binomial',
    stanParamNames: ['alpha', 'beta'],
    transformParams: (params) => {
      const [p, r] = params
      return [r || '1', p ? `${p} / (1.0 - ${p})` : '1']
    },
  },
  dpar: {
    stanName: 'pareto',
    stanParamNames: ['y_min', 'alpha'],
    transformParams: (params) => {
      const [a, b] = params
      return [a || '1', b || '1']
    },
  },
  ddexp: {
    stanName: 'double_exponential',
    stanParamNames: ['mu', 'sigma'],
    transformParams: (params) => {
      const [mu, tau] = params
      return [mu || '0', tau ? `1.0 / ${tau}` : '1']
    },
  },
  dlogis: {
    stanName: 'logistic',
    stanParamNames: ['mu', 's'],
    transformParams: (params) => [params[0] || '0', params[1] || '1'],
  },
  df: {
    stanName: 'inv_gamma',
    stanParamNames: ['alpha', 'beta'],
    transformParams: (params) => [params[0] || '1', params[1] || '1'],
  },
}

function convertBugsName(name: string): string {
  return name.replace(/\./g, '_')
}

function convertExpression(expr: string): string {
  let result = expr.replace(/([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_])/g, '$1_$2')
  result = result.replace(/\b(pow)\s*\(/g, '(')
  if (/\bpow\b/.test(expr)) {
    result = result.replace(/\bpow\(([^,]+),\s*([^)]+)\)/g, '($1) ^ ($2)')
  }
  result = result.replace(/\bloggam\b/g, 'lgamma')
  result = result.replace(/\blogfact\b/g, 'log_factorial')
  result = result.replace(/\bilogit\b/g, 'inv_logit')
  result = result.replace(/\blogistic\b/g, 'inv_logit')
  result = result.replace(/\bphi\b/g, 'Phi')
  result = result.replace(/\bprobit\b/g, 'inv_Phi')
  result = result.replace(/\bcloglog\b/g, 'log(-log(1 - ')
  result = result.replace(/\bicloglog\b/g, '1 - exp(-exp(')
  result = result.replace(/\bcexpexp\b/g, '1 - exp(-exp(')
  result = result.replace(/\binprod\b/g, 'dot_product')
  result = result.replace(/\bstep\b/g, '(x > 0 ? 1 : 0)')
  result = result.replace(/\b_step\b/g, '(x > 0 ? 1 : 0)')
  result = result.replace(/\bequals\(([^,]+),\s*([^)]+)\)/g, '($1 == $2 ? 1 : 0)')
  result = result.replace(/\blogdet\b/g, 'log_determinant')
  result = result.replace(/\bmexp\b/g, 'matrix_exp')
  result = result.replace(/\bsoftplus\b/g, 'log1p_exp')
  return result
}

interface NodeClassification {
  stochasticParams: GraphNode[]
  deterministicNodes: GraphNode[]
  observedNodes: GraphNode[]
  constantNodes: GraphNode[]
  plates: GraphNode[]
}

function classifyNodes(nodes: GraphNode[]): NodeClassification {
  const stochasticParams: GraphNode[] = []
  const deterministicNodes: GraphNode[] = []
  const observedNodes: GraphNode[] = []
  const constantNodes: GraphNode[] = []
  const plates: GraphNode[] = []

  for (const node of nodes) {
    switch (node.nodeType) {
      case 'stochastic':
        stochasticParams.push(node)
        break
      case 'observed':
        observedNodes.push(node)
        break
      case 'deterministic':
        deterministicNodes.push(node)
        break
      case 'constant':
        constantNodes.push(node)
        break
      case 'plate':
        plates.push(node)
        break
    }
  }
  return { stochasticParams, deterministicNodes, observedNodes, constantNodes, plates }
}

function getPlateAncestors(node: GraphNode, nodeMap: Map<string, GraphNode>): GraphNode[] {
  const ancestors: GraphNode[] = []
  let current = node
  while (current.parent) {
    const parent = nodeMap.get(current.parent)
    if (parent && parent.nodeType === 'plate') {
      ancestors.unshift(parent)
      current = parent
    } else {
      break
    }
  }
  return ancestors
}

function getLoopDimensions(
  node: GraphNode,
  nodeMap: Map<string, GraphNode>
): { variable: string; range: string }[] {
  const plates = getPlateAncestors(node, nodeMap)
  return plates.map((p) => ({
    variable: p.loopVariable || 'i',
    range: convertBugsName(p.loopRange || '1:N'),
  }))
}

function getArrayDimsFromNode(
  node: GraphNode,
  nodeMap: Map<string, GraphNode>,
  allPlates: GraphNode[]
): string[] {
  const indices = node.indices?.trim()
  if (indices) {
    const varToUpper = new Map<string, string>()
    for (const plate of allPlates) {
      const loopVar = plate.loopVariable || 'i'
      const range = convertBugsName(plate.loopRange || '1:N')
      const parts = range.split(':')
      const upper = parts.length === 2 ? parts[1].trim() : range
      varToUpper.set(loopVar, upper)
    }
    const indexParts = indices.split(',').map((s) => s.trim())
    const dims: string[] = []
    for (const idx of indexParts) {
      const upper = varToUpper.get(idx)
      if (upper) dims.push(upper)
    }
    return dims
  }
  const plateDims = getLoopDimensions(node, nodeMap)
  return plateDims.map((d) => {
    const parts = d.range.split(':')
    return parts.length === 2 ? parts[1] : d.range
  })
}

function inferStanType(
  node: GraphNode,
  nodeMap: Map<string, GraphNode>,
  allPlates: GraphNode[]
): string {
  const dims = getArrayDimsFromNode(node, nodeMap, allPlates)
  const dist = node.distribution

  let baseType = 'real'
  if (
    dist === 'dbern' ||
    dist === 'dbin' ||
    dist === 'dpois' ||
    dist === 'dcat' ||
    dist === 'dnegbin' ||
    dist === 'dgeom' ||
    dist === 'dhyper' ||
    dist === 'dbetabin'
  ) {
    baseType = 'int'
  }

  if (dist === 'dmnorm' || dist === 'dmt') baseType = 'vector[K]'
  if (dist === 'dwish') baseType = 'matrix[K, K]'
  if (dist === 'ddirich') baseType = 'simplex[K]'
  if (dist === 'dmulti') baseType = 'array[] int'

  if (
    dims.length > 0 &&
    !baseType.startsWith('vector') &&
    !baseType.startsWith('matrix') &&
    !baseType.startsWith('simplex')
  ) {
    return `array[${dims.join(', ')}] ${baseType}`
  }

  return baseType
}

function formatStanDistribution(
  node: GraphNode,
  nameToNode: Map<string, GraphNode>
): { stanDist: string; stanParams: string } | null {
  const dist = node.distribution
  if (!dist) return null

  const mapping = DISTRIBUTION_MAP[dist]
  if (!mapping) {
    const rawParams = collectRawParams(node, nameToNode)
    return { stanDist: dist, stanParams: rawParams.join(', ') }
  }

  const rawParams = collectRawParams(node, nameToNode)
  const transformed = mapping.transformParams(rawParams, node)
  return { stanDist: mapping.stanName, stanParams: transformed.join(', ') }
}

function collectRawParams(node: GraphNode, nameToNode: Map<string, GraphNode>): string[] {
  const params: string[] = []
  for (const key of ['param1', 'param2', 'param3'] as const) {
    const val = node[key]
    if (val && String(val).trim() !== '') {
      params.push(formatStanParam(String(val).trim(), nameToNode))
    }
  }
  return params
}

function formatStanParam(raw: string, nameToNode: Map<string, GraphNode>): string {
  const p = raw.trim()
  if (!p) return p
  if (/^[+-]?(?:\d+\.?\d*|\d*\.\d+)(?:[eE][+-]?\d+)?$/.test(p)) {
    return p
  }
  if (/\[[^\]]+\]\s*$/.test(p)) return convertBugsName(p)
  if (/[()]/.test(p)) {
    return convertExpression(p)
  }
  const ref = nameToNode.get(p)
  if (ref && ref.indices && String(ref.indices).trim() !== '') {
    return `${convertBugsName(p)}[${ref.indices}]`
  }
  return convertBugsName(p)
}

function buildTopologicalOrder(nodes: GraphNode[], edges: GraphEdge[]): string[] {
  const nodeInDegree: Record<string, number> = {}
  const adjacencyList: Record<string, string[]> = {}
  nodes.forEach((node) => {
    nodeInDegree[node.id] = 0
    adjacencyList[node.id] = []
  })
  edges.forEach((edge) => {
    if (adjacencyList[edge.source] && nodeInDegree[edge.target] !== undefined) {
      adjacencyList[edge.source].push(edge.target)
      nodeInDegree[edge.target]++
    }
  })
  const queue = nodes.filter((n) => nodeInDegree[n.id] === 0).map((n) => n.id)
  const sorted: string[] = []
  while (queue.length > 0) {
    const id = queue.shift()!
    sorted.push(id)
    adjacencyList[id]?.forEach((child) => {
      if (nodeInDegree[child] !== undefined) {
        nodeInDegree[child]--
        if (nodeInDegree[child] === 0) queue.push(child)
      }
    })
  }
  return sorted
}

function needsBoundsFromDistribution(dist: string | undefined): string {
  if (!dist) return ''
  switch (dist) {
    case 'dgamma':
    case 'dexp':
    case 'dchisqr':
    case 'dweib':
    case 'dlnorm':
    case 'dpar':
      return '<lower=0>'
    case 'dbeta':
      return '<lower=0, upper=1>'
    case 'dunif':
      return ''
    default:
      return ''
  }
}

// Scans all node expressions and params for identifiers that are not already
// declared as graph nodes, loop variables, or plate size variables.
// Returns them with their inferred Stan type (array dims if subscripted).
function findUndeclaredDataVars(
  nodes: GraphNode[],
  plates: GraphNode[],
  plateSizeVars: Set<string>
): { stanName: string; dims: string[] }[] {
  const knownBugsNames = new Set<string>()
  const loopVars = new Set<string>()
  const loopVarToUpper = new Map<string, string>()

  for (const n of nodes) {
    if (n.nodeType === 'plate') {
      const lv = n.loopVariable || 'i'
      loopVars.add(lv)
      const range = convertBugsName(n.loopRange || '1:N')
      const parts = range.split(':')
      const upper = parts.length === 2 ? parts[1].trim() : range
      loopVarToUpper.set(lv, upper)
    } else {
      knownBugsNames.add(n.name)
    }
  }

  const allExprs: string[] = []
  for (const n of nodes) {
    if (n.nodeType === 'plate') continue
    for (const val of [n.equation, n.param1, n.param2, n.param3, n.censorLower, n.censorUpper]) {
      if (val) allExprs.push(String(val))
    }
  }

  // Match dotted-identifiers (BUGS names) optionally followed by [subscript].
  // The lookbehind (?<![0-9.]) prevents matching the exponent letter in numeric
  // literals like 1.0E-4 where E is preceded by a digit.
  const IDENT_RE = /(?<![0-9.])([A-Za-z_][A-Za-z0-9_.]*)(\s*)(\[([^\]]*)\])?/g
  const undeclared = new Map<string, Set<string>>()

  for (const expr of allExprs) {
    IDENT_RE.lastIndex = 0
    let match: RegExpExecArray | null
    while ((match = IDENT_RE.exec(expr)) !== null) {
      const bugsName = match[1]
      const subscript = match[4]?.trim()
      const charAfterIdent = expr.charAt(match.index! + bugsName.length)

      // Skip function calls (identifier immediately followed by '(')
      if (charAfterIdent === '(') continue
      // Skip loop variable bare names
      if (loopVars.has(bugsName)) continue
      // Skip known graph node names (dotted, as-is from JSON)
      if (knownBugsNames.has(bugsName)) continue
      // Skip numeric tokens
      if (/^\d/.test(bugsName)) continue

      const stanName = convertBugsName(bugsName)
      if (plateSizeVars.has(stanName)) continue
      if (loopVars.has(stanName)) continue

      if (!undeclared.has(stanName)) undeclared.set(stanName, new Set())

      if (subscript) {
        for (const sub of subscript.split(',').map((s) => s.trim())) {
          const upper = loopVarToUpper.get(sub)
          if (upper) undeclared.get(stanName)!.add(upper)
        }
      }
    }
  }

  return [...undeclared.entries()].map(([stanName, dimsSet]) => ({
    stanName,
    dims: [...dimsSet],
  }))
}

export function useStanCodeGenerator(elements: Ref<GraphElement[]>) {
  const generatedStanCode = computed(() => {
    const nodes = elements.value.filter((el: GraphElement) => el.type === 'node') as GraphNode[]
    const edges = elements.value.filter((el: GraphElement) => el.type === 'edge') as GraphEdge[]
    const nodeMap = new Map(nodes.map((n) => [n.id, n]))
    const nameToNode = new Map(nodes.map((n) => [n.name, n]))

    if (nodes.length === 0) {
      return '// Your Stan model will appear here...\n'
    }

    const { stochasticParams, deterministicNodes, observedNodes, constantNodes, plates } =
      classifyNodes(nodes)
    const topoOrder = buildTopologicalOrder(nodes, edges)
    const topoIndex = new Map(topoOrder.map((id, i) => [id, i]))

    const sortByTopo = (a: GraphNode, b: GraphNode) =>
      (topoIndex.get(a.id) ?? 0) - (topoIndex.get(b.id) ?? 0)

    const dataDeclarations: string[] = []
    const parameterDeclarations: string[] = []
    const transformedParamLines: string[] = []

    const plateSizeVars = new Set<string>()
    for (const plate of plates) {
      const range = plate.loopRange || ''
      const converted = convertBugsName(range)
      const parts = converted.split(':')
      if (parts.length === 2) {
        const upper = parts[1].trim()
        if (/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(upper)) {
          plateSizeVars.add(upper)
        }
      }
    }
    for (const v of plateSizeVars) {
      dataDeclarations.push(`  int<lower=1> ${v};`)
    }

    for (const node of constantNodes.sort(sortByTopo)) {
      const stanName = convertBugsName(node.name)
      const dims = getArrayDimsFromNode(node, nodeMap, plates)
      if (dims.length > 0) {
        dataDeclarations.push(`  array[${dims.join(', ')}] real ${stanName};`)
      } else {
        dataDeclarations.push(`  real ${stanName};`)
      }
    }

    for (const node of observedNodes.sort(sortByTopo)) {
      const stanName = convertBugsName(node.name)
      const stanType = inferStanType(node, nodeMap, plates)
      dataDeclarations.push(`  ${stanType} ${stanName};`)

      const cl = node.censorLower ? String(node.censorLower).trim() : ''
      const cu = node.censorUpper ? String(node.censorUpper).trim() : ''
      if (cl || cu) {
        const dims = getArrayDimsFromNode(node, nodeMap, plates)
        const censorBound = cl || cu
        const rawBoundName = censorBound.replace(/\[.*$/, '')
        const stanBoundName = convertBugsName(rawBoundName)
        if (dims.length > 0) {
          dataDeclarations.push(`  array[${dims.join(', ')}] real ${stanBoundName};`)
          dataDeclarations.push(`  array[${dims.join(', ')}] int ${stanName}_is_obs;`)
        } else {
          dataDeclarations.push(`  real ${stanBoundName};`)
          dataDeclarations.push(`  int ${stanName}_is_obs;`)
        }
      }
    }

    // Detect any identifiers used in equations/params that are not graph nodes.
    // These are external data covariates (e.g. Base[j], Trt[j], log.Base4.bar).
    const alreadyDeclared = new Set(
      dataDeclarations.map((d) => d.trim().split(/\s+/).pop()!.replace(';', ''))
    )
    for (const { stanName, dims } of findUndeclaredDataVars(nodes, plates, plateSizeVars)) {
      if (alreadyDeclared.has(stanName)) continue
      if (dims.length > 0) {
        dataDeclarations.push(`  array[${dims.join(', ')}] real ${stanName};`)
      } else {
        dataDeclarations.push(`  real ${stanName};`)
      }
      alreadyDeclared.add(stanName)
    }

    for (const node of stochasticParams.sort(sortByTopo)) {
      const stanName = convertBugsName(node.name)
      const dims = getArrayDimsFromNode(node, nodeMap, plates)
      const bounds = needsBoundsFromDistribution(node.distribution)

      const dist = node.distribution
      let baseType = 'real'
      if (dist === 'dmnorm' || dist === 'dmt') baseType = 'vector[K]'
      else if (dist === 'dwish') baseType = 'cov_matrix[K]'
      else if (dist === 'ddirich') baseType = 'simplex[K]'

      if (
        dims.length > 0 &&
        !baseType.startsWith('vector') &&
        !baseType.startsWith('cov_matrix') &&
        !baseType.startsWith('simplex')
      ) {
        parameterDeclarations.push(`  array[${dims.join(', ')}] real${bounds} ${stanName};`)
      } else {
        parameterDeclarations.push(`  ${baseType}${bounds} ${stanName};`)
      }
    }

    const deterministic = deterministicNodes.sort(sortByTopo)
    for (const node of deterministic) {
      const stanName = convertBugsName(node.name)
      const dims = getArrayDimsFromNode(node, nodeMap, plates)
      if (dims.length > 0) {
        transformedParamLines.push(`  array[${dims.join(', ')}] real ${stanName};`)
      } else {
        transformedParamLines.push(`  real ${stanName};`)
      }
    }

    const plateChildren = new Map<string, GraphNode[]>()
    const rootNodes: GraphNode[] = []
    for (const node of nodes) {
      if (node.nodeType === 'plate') continue
      if (node.parent) {
        const list = plateChildren.get(node.parent) || []
        list.push(node)
        plateChildren.set(node.parent, list)
      } else {
        rootNodes.push(node)
      }
    }

    const generateBlockStatements = (
      nodesToProcess: GraphNode[],
      indent: string,
      blockType: 'transformed' | 'model'
    ): string[] => {
      const lines: string[] = []
      const sorted = [...nodesToProcess].sort(sortByTopo)

      for (const node of sorted) {
        if (node.nodeType === 'plate') {
          const plateVar = node.loopVariable || 'i'
          const plateRange = convertBugsName(node.loopRange || '1:N')
          const rangeParts = plateRange.split(':')
          const lower = rangeParts[0] || '1'
          const upper = rangeParts.length === 2 ? rangeParts[1] : plateRange
          lines.push(`${indent}for (${plateVar} in ${lower}:${upper}) {`)
          const children = plateChildren.get(node.id) || []
          const plateNodes = children.filter((c) => {
            if (blockType === 'transformed') return c.nodeType === 'deterministic'
            return c.nodeType === 'stochastic' || c.nodeType === 'observed'
          })
          const nestedPlates = plates.filter((p) => p.parent === node.id)
          lines.push(
            ...generateBlockStatements([...plateNodes, ...nestedPlates], indent + '  ', blockType)
          )
          lines.push(`${indent}}`)
          continue
        }

        const stanName = convertBugsName(node.name)
        const idx = node.indices ? `[${node.indices}]` : ''

        if (blockType === 'transformed' && node.nodeType === 'deterministic') {
          if (node.equation) {
            const expr = convertExpression(node.equation)
            lines.push(`${indent}${stanName}${idx} = ${expr};`)
          }
        }

        if (
          blockType === 'model' &&
          (node.nodeType === 'stochastic' || node.nodeType === 'observed')
        ) {
          const distInfo = formatStanDistribution(node, nameToNode)
          if (distInfo) {
            const cl = node.censorLower ? String(node.censorLower).trim() : ''
            const cu = node.censorUpper ? String(node.censorUpper).trim() : ''
            const hasCensoring = !!(cl || cu)

            if (hasCensoring && node.nodeType === 'observed') {
              const censorBound = cl || cu
              const stanBound = convertExpression(convertBugsName(censorBound))
              const cdfFunc = cl ? `${distInfo.stanDist}_lccdf` : `${distInfo.stanDist}_lcdf`

              const isObsName = `${stanName}_is_obs`
              lines.push(`${indent}if (${isObsName}${idx} == 1) {`)
              lines.push(
                `${indent}  ${stanName}${idx} ~ ${distInfo.stanDist}(${distInfo.stanParams});`
              )
              lines.push(`${indent}} else {`)
              lines.push(`${indent}  target += ${cdfFunc}(${stanBound} | ${distInfo.stanParams});`)
              lines.push(`${indent}}`)
            } else {
              lines.push(
                `${indent}${stanName}${idx} ~ ${distInfo.stanDist}(${distInfo.stanParams});`
              )
            }
          }
        }
      }
      return lines
    }

    const rootDeterministic = rootNodes.filter((n) => n.nodeType === 'deterministic')
    const rootStochastic = rootNodes.filter(
      (n) => n.nodeType === 'stochastic' || n.nodeType === 'observed'
    )
    const rootPlates = plates.filter((p) => !p.parent)

    const tpStatements = generateBlockStatements(
      [...rootDeterministic, ...rootPlates],
      '  ',
      'transformed'
    )

    const modelStatements = generateBlockStatements(
      [...rootStochastic, ...rootPlates],
      '  ',
      'model'
    )

    const sections: string[] = []

    if (dataDeclarations.length > 0) {
      sections.push(`data {\n${dataDeclarations.join('\n')}\n}`)
    }

    if (parameterDeclarations.length > 0) {
      sections.push(`parameters {\n${parameterDeclarations.join('\n')}\n}`)
    }

    if (tpStatements.length > 0) {
      const tpDeclBlock =
        transformedParamLines.length > 0 ? transformedParamLines.join('\n') + '\n' : ''
      sections.push(`transformed parameters {\n${tpDeclBlock}${tpStatements.join('\n')}\n}`)
    }

    if (modelStatements.length > 0) {
      sections.push(`model {\n${modelStatements.join('\n')}\n}`)
    }

    if (sections.length === 0) {
      return '// Empty model\n'
    }

    return sections.join('\n\n') + '\n'
  })

  return { generatedStanCode }
}

function convertDataKeys(obj: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {}
  for (const [key, val] of Object.entries(obj)) {
    result[convertBugsName(key)] = val
  }
  return result
}

function buildIsObsIndicator(arr: unknown): unknown {
  if (Array.isArray(arr)) {
    return arr.map((item) => {
      if (Array.isArray(item)) return buildIsObsIndicator(item)
      return item === null || item === undefined ? 0 : 1
    })
  }
  return arr === null || arr === undefined ? 0 : 1
}

function fillMissingWithCensor(obs: unknown, cens: unknown): unknown {
  if (Array.isArray(obs) && Array.isArray(cens)) {
    return obs.map((item, i) => fillMissingWithCensor(item, cens[i]))
  }
  if (obs === null || obs === undefined) {
    return typeof cens === 'number' ? cens : 0
  }
  return obs
}

export function generateStanDataJson(
  data: Record<string, unknown>,
  censoredFields?: { varName: string; censorBoundName: string }[]
): string {
  const converted = convertDataKeys(data)

  if (censoredFields) {
    for (const { varName, censorBoundName } of censoredFields) {
      const stanVar = convertBugsName(varName)
      const stanBound = convertBugsName(censorBoundName)
      const obsData = converted[stanVar]
      const cenData = converted[stanBound]

      if (obsData !== undefined) {
        converted[`${stanVar}_is_obs`] = buildIsObsIndicator(obsData)
        if (cenData !== undefined) {
          converted[stanVar] = fillMissingWithCensor(obsData, cenData)
        }
      }
    }
  }

  return JSON.stringify(converted, null, 2)
}

export function generateStanInitsJson(inits: Record<string, unknown>): string {
  return JSON.stringify(convertDataKeys(inits), null, 2)
}

export function extractCensoredFields(
  elements: GraphElement[]
): { varName: string; censorBoundName: string }[] {
  const nodes = elements.filter((el) => el.type === 'node') as GraphNode[]
  const result: { varName: string; censorBoundName: string }[] = []
  for (const node of nodes) {
    if (node.nodeType !== 'observed') continue
    const cl = node.censorLower ? String(node.censorLower).trim() : ''
    const cu = node.censorUpper ? String(node.censorUpper).trim() : ''
    const bound = cl || cu
    if (!bound) continue
    const boundName = bound.replace(/\[.*$/, '')
    result.push({ varName: node.name, censorBoundName: boundName })
  }
  return result
}

export interface StanScriptInput {
  modelCode: string
  data: Record<string, unknown>
  inits: Record<string, unknown>
  censoredFields?: { varName: string; censorBoundName: string }[]
  settings: {
    n_samples: number
    n_adapts: number
    n_chains: number
    seed?: number | null
  }
}

export function generateStanStandaloneScript(input: StanScriptInput): string {
  const { modelCode, data, inits, censoredFields, settings } = input

  const dataJson = generateStanDataJson(data, censoredFields)
  const initsJson = generateStanInitsJson(inits)

  const nSamples = settings?.n_samples ?? 1000
  const nWarmup = settings?.n_adapts ?? 1000
  const nChains = settings?.n_chains ?? 1
  const seed = typeof settings?.seed === 'number' ? settings.seed : 12345

  return `#!/usr/bin/env python3
"""
Stan model generated by DoodleBUGS
Run with CmdStanPy: pip install cmdstanpy
"""
import json
import os
import cmdstanpy

model_code = """
${modelCode}"""

data = json.loads("""
${dataJson}
""")

inits = json.loads("""
${initsJson}
""")

model_dir = os.path.join(os.path.dirname(__file__), "stan_model")
os.makedirs(model_dir, exist_ok=True)

model_file = os.path.join(model_dir, "model.stan")
with open(model_file, "w") as f:
    f.write(model_code)

data_file = os.path.join(model_dir, "data.json")
with open(data_file, "w") as f:
    json.dump(data, f)

inits_file = os.path.join(model_dir, "inits.json")
with open(inits_file, "w") as f:
    json.dump(inits, f)

model = cmdstanpy.CmdStanModel(stan_file=model_file)
fit = model.sample(
    data=data_file,
    inits=inits_file,
    chains=${nChains},
    iter_warmup=${nWarmup},
    iter_sampling=${nSamples},
    seed=${seed},
)

print(fit.summary())
print(fit.diagnose())
`
}
