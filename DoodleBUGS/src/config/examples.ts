export interface ExampleModelConfig {
  id: string
  name: string
  url?: string
}

export const examples: ExampleModelConfig[] = [
  {
    id: 'rats',
    name: 'Rats Model',
    // url: 'https://raw.githubusercontent.com/shravanngoswamii/experimental/refs/heads/main/model.json'
  },
  // Add other models here
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
