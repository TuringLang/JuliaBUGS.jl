import type { Core, LayoutOptions } from 'cytoscape'

export function useGraphLayout() {
  const smartFit = (cy: Core, animate: boolean = true) => {
    const eles = cy.elements()
    if (eles.length === 0) return

    const padding = 50
    const w = cy.width()
    const h = cy.height()
    const bb = eles.boundingBox()

    if (bb.w === 0 || bb.h === 0) return

    const zoomX = (w - 2 * padding) / bb.w
    const zoomY = (h - 2 * padding) / bb.h
    let targetZoom = Math.min(zoomX, zoomY)
    targetZoom = Math.min(targetZoom, 0.8)

    const targetPan = {
      x: (w - targetZoom * (bb.x1 + bb.x2)) / 2,
      y: (h - targetZoom * (bb.y1 + bb.y2)) / 2,
    }

    if (animate) {
      cy.animate({
        zoom: targetZoom,
        pan: targetPan,
        duration: 500,
        easing: 'ease-in-out-cubic',
      })
    } else {
      cy.viewport({ zoom: targetZoom, pan: targetPan })
    }
  }

  const getLayoutOptions = (layoutName: string): LayoutOptions => {
    const layoutOptionsMap: Record<string, LayoutOptions> = {
      dagre: {
        name: 'dagre',
        animate: true,
        animationDuration: 500,
        fit: false,
        padding: 50,
      } as unknown as LayoutOptions,
      fcose: {
        name: 'fcose',
        animate: true,
        animationDuration: 500,
        fit: false,
        padding: 50,
        randomize: false,
        quality: 'proof',
      } as unknown as LayoutOptions,
      cola: {
        name: 'cola',
        animate: true,
        fit: false,
        padding: 50,
        refresh: 1,
        avoidOverlap: true,
        infinite: false,
        centerGraph: true,
        flow: { axis: 'y', minSeparation: 30 },
        handleDisconnected: false,
        randomize: false,
      } as unknown as LayoutOptions,
      klay: {
        name: 'klay',
        animate: true,
        animationDuration: 500,
        fit: false,
        padding: 50,
        klay: { direction: 'RIGHT', edgeRouting: 'SPLINES', nodePlacement: 'LINEAR_SEGMENTS' },
      } as unknown as LayoutOptions,
      preset: { name: 'preset', fit: false, padding: 50 } as unknown as LayoutOptions,
    }

    return layoutOptionsMap[layoutName] || layoutOptionsMap.preset
  }

  const applyLayout = (cy: Core, layoutName: string, onComplete?: () => void) => {
    const options = getLayoutOptions(layoutName)

    if (onComplete) {
      cy.one('layoutstop', onComplete)
    }

    cy.layout(options).run()
  }

  const applyLayoutWithFit = (cy: Core, layoutName: string) => {
    applyLayout(cy, layoutName, () => smartFit(cy, true))
  }

  return {
    smartFit,
    getLayoutOptions,
    applyLayout,
    applyLayoutWithFit,
  }
}
