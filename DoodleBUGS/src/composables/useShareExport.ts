import { ref } from 'vue'
import type { GraphElement, GraphNode, NodeType } from '../types'

const keyMap: Record<string, string> = {
  id: 'i',
  name: 'n',
  type: 't',
  nodeType: 'nt',
  position: 'p',
  parent: 'pa',
  distribution: 'di',
  equation: 'eq',
  observed: 'ob',
  indices: 'id',
  loopVariable: 'lv',
  loopRange: 'lr',
  param1: 'p1',
  param2: 'p2',
  param3: 'p3',
  source: 's',
  target: 'tg',
  x: 'x',
  y: 'y',
}

const nodeTypeMap: Record<string, number> = {
  stochastic: 1,
  deterministic: 2,
  constant: 3,
  observed: 4,
  plate: 5,
}

const reverseNodeTypeMap: Record<number, string> = Object.fromEntries(
  Object.entries(nodeTypeMap).map(([k, v]) => [v, k])
)

export function useShareExport() {
  const shareUrl = ref('')

  const compressAndEncode = async (jsonStr: string): Promise<string> => {
    try {
      if (!window.CompressionStream) throw new Error('CompressionStream not supported')
      const stream = new Blob([jsonStr]).stream()
      const compressedStream = stream.pipeThrough(new CompressionStream('gzip'))
      const response = new Response(compressedStream)
      const blob = await response.blob()
      const buffer = await blob.arrayBuffer()
      const bytes = new Uint8Array(buffer)
      let binaryStr = ''
      for (let i = 0; i < bytes.byteLength; i++) {
        binaryStr += String.fromCharCode(bytes[i])
      }
      return 'gz_' + btoa(binaryStr)
    } catch {
      return btoa(unescape(encodeURIComponent(jsonStr)))
    }
  }

  const decodeAndDecompress = async (encoded: string): Promise<string> => {
    try {
      if (encoded.startsWith('gz_')) {
        if (!window.DecompressionStream) throw new Error('DecompressionStream not supported')
        const base64 = encoded.substring(3)
        const binaryStr = atob(base64)
        const len = binaryStr.length
        const bytes = new Uint8Array(len)
        for (let i = 0; i < len; i++) {
          bytes[i] = binaryStr.charCodeAt(i)
        }
        const stream = new Blob([bytes]).stream()
        const decompressedStream = stream.pipeThrough(new DecompressionStream('gzip'))
        const response = new Response(decompressedStream)
        return await response.text()
      }
      return decodeURIComponent(escape(atob(encoded)))
    } catch (e) {
      console.error('Decompression failed, trying legacy decode:', e)
      return decodeURIComponent(escape(atob(encoded)))
    }
  }

  const minifyGraph = (elems: GraphElement[]): Record<string, unknown>[] => {
    return elems.map((el) => {
      const min: Record<string, unknown> = {}
      if (el.type === 'node') {
        const node = el as GraphNode
        min[keyMap.id] = node.id.replace('node_', '')
        min[keyMap.name] = node.name
        min[keyMap.type] = 0
        min[keyMap.nodeType] = nodeTypeMap[node.nodeType]
        min[keyMap.position] = [Math.round(node.position.x), Math.round(node.position.y)]
        if (node.parent) min[keyMap.parent] = node.parent.replace('node_', '').replace('plate_', '')
        if (node.distribution) min[keyMap.distribution] = node.distribution
        if (node.equation) min[keyMap.equation] = node.equation
        if (node.observed) min[keyMap.observed] = 1
        if (node.indices) min[keyMap.indices] = node.indices
        if (node.loopVariable) min[keyMap.loopVariable] = node.loopVariable
        if (node.loopRange) min[keyMap.loopRange] = node.loopRange
        if (node.param1) min[keyMap.param1] = node.param1
        if (node.param2) min[keyMap.param2] = node.param2
        if (node.param3) min[keyMap.param3] = node.param3
      } else {
        min[keyMap.id] = el.id.replace('edge_', '')
        min[keyMap.type] = 1
        min[keyMap.source] = el.source.replace('node_', '').replace('plate_', '')
        min[keyMap.target] = el.target.replace('node_', '').replace('plate_', '')
      }
      return min
    })
  }

  const expandGraph = (minified: Record<string, unknown>[]): GraphElement[] => {
    return minified.map((min) => {
      if (min[keyMap.type] === 0) {
        const nodeTypeNum = min[keyMap.nodeType] as number
        const minId = min[keyMap.id] as string
        
        // Handle plate vs regular node IDs
        const id = minId.startsWith('node_') || minId.startsWith('plate_')
          ? minId
          : (nodeTypeNum === 5 ? 'plate_' : 'node_') + minId

        const node: Partial<GraphNode> = {
          type: 'node',
          id,
          name: min[keyMap.name] as string,
          nodeType: reverseNodeTypeMap[nodeTypeNum] as NodeType,
          position: {
            x: min[keyMap.position] && !isNaN((min[keyMap.position] as number[])[0]) 
              ? (min[keyMap.position] as number[])[0] 
              : 0,
            y: min[keyMap.position] && !isNaN((min[keyMap.position] as number[])[1]) 
              ? (min[keyMap.position] as number[])[1] 
              : 0,
          },
        }
        
        if (min[keyMap.parent]) {
          const pid = min[keyMap.parent] as string
          node.parent = pid.startsWith('plate_') || pid.startsWith('node_') 
            ? pid 
            : 'plate_' + pid
        }
        if (min[keyMap.distribution]) node.distribution = min[keyMap.distribution] as string
        if (min[keyMap.equation]) node.equation = min[keyMap.equation] as string
        if (min[keyMap.observed]) node.observed = true
        if (min[keyMap.indices]) node.indices = min[keyMap.indices] as string
        if (min[keyMap.loopVariable]) node.loopVariable = min[keyMap.loopVariable] as string
        if (min[keyMap.loopRange]) node.loopRange = min[keyMap.loopRange] as string
        if (min[keyMap.param1]) node.param1 = min[keyMap.param1] as string
        if (min[keyMap.param2]) node.param2 = min[keyMap.param2] as string
        if (min[keyMap.param3]) node.param3 = min[keyMap.param3] as string
        return node as GraphElement
      } else {
        const minId = min[keyMap.id] as string
        const minSource = min[keyMap.source] as string
        const minTarget = min[keyMap.target] as string
        
        const edge = {
          type: 'edge' as const,
          id: minId.startsWith('edge_') ? minId : 'edge_' + minId,
          source: minSource.startsWith('node_') || minSource.startsWith('plate_')
            ? minSource
            : 'node_' + minSource,
          target: minTarget.startsWith('node_') || minTarget.startsWith('plate_')
            ? minTarget
            : 'node_' + minTarget,
        }
        return edge as GraphElement
      }
    })
  }

  const generateShareLink = async (payload: object) => {
    try {
      const base64 = await compressAndEncode(JSON.stringify(payload))
      const baseUrl = window.location.origin + window.location.pathname
      shareUrl.value = `${baseUrl}?share=${encodeURIComponent(base64)}`
    } catch (e) {
      console.error('Failed to generate share link:', e)
    }
  }

  return {
    shareUrl,
    compressAndEncode,
    decodeAndDecompress,
    minifyGraph,
    expandGraph,
    generateShareLink,
  }
}
