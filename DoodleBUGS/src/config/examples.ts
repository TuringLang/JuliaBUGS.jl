// Import local models directly to bundle them into the widget JS
// Note: Ensure these files exist and use the Unified JSON format
import ratsModel from '../../public/examples/rats/model.json'

export type ModelSourceType = 'local' | 'github' | 'url'

export interface ExampleModelConfig {
  id: string
  name: string
  type: ModelSourceType
  // For local bundled models, we pass the imported JSON object directly
  data?: unknown 
  // For remote models, we pass the URL
  url?: string
}

export const examples: ExampleModelConfig[] = [
  {
    id: 'rats',
    name: 'Rats Model',
    type: 'local',
    data: ratsModel, // Bundled directly
  },
  {
    id: 'rat-2',
    name: 'Rats (Fetch from Github URL)',
    type: 'github',
    url: 'https://raw.githubusercontent.com/shravanngoswamii/experimental/refs/heads/main/model.json'
  }
]

// Helper to check if a string is a URL
export const isUrl = (str: string) => {
  try {
    new URL(str);
    return true;
  } catch {
    return false;
  }
}
