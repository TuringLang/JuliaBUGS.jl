export interface ExampleModelConfig {
  id: string
  name: string
  url?: string
}

export const examples: ExampleModelConfig[] = [
  {
    id: 'rats',
    name: 'Rats Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/rats/model.json',
  },
  {
    id: 'pumps',
    name: 'Pumps Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/pumps/model.json',
  },
  {
    id: 'seeds',
    name: 'Seeds Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/seeds/model.json',
  },
  // Add other models here
]

// Helper to check if a string is a URL
export const isUrl = (str: string) => {
  try {
    new URL(str)
    return true
  } catch {
    return false
  }
}
