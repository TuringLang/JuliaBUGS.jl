import { ref } from 'vue'

export interface ImportedGraphData {
  name?: string
  elements: unknown[]
  dataContent?: string
  layout?: string
}

export function useImportExport() {
  const importedGraphData = ref<ImportedGraphData | null>(null)

  const processGraphFile = (file: File): Promise<ImportedGraphData> => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = (e) => {
        try {
          const content = e.target?.result as string
          const data = JSON.parse(content)
          if (data.elements && Array.isArray(data.elements)) {
            importedGraphData.value = data
            resolve(data)
          } else {
            reject(new Error('Invalid graph JSON file.'))
          }
        } catch (err) {
          console.error(err)
          reject(new Error('Failed to parse file.'))
        }
      }
      reader.onerror = () => reject(new Error('Failed to read file.'))
      reader.readAsText(file)
    })
  }

  const clearImportedData = () => {
    importedGraphData.value = null
  }

  return {
    importedGraphData,
    processGraphFile,
    clearImportedData,
  }
}
