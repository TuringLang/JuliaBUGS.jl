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
  {
    id: 'surgical',
    name: 'Surgical Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/surgical/model.json',
  },
  {
    id: 'dyes',
    name: 'Dyes Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/dyes/model.json',
  },
  {
    id: 'blockers',
    name: 'Blockers Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/blockers/model.json',
  },
  {
    id: 'salm',
    name: 'Salm Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/salm/model.json',
  },
  {
    id: 'equiv',
    name: 'Equiv Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/equiv/model.json',
  },
  {
    id: 'oxford',
    name: 'Oxford Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/oxford/model.json',
  },
  {
    id: 'epil',
    name: 'Epilepsy Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/epil/model.json',
  },
  {
    id: 'mice',
    name: 'Mice Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/mice/model.json',
  },
  {
    id: 'kidney',
    name: 'Kidney Model',
    url: 'https://raw.githubusercontent.com/TuringLang/JuliaBUGS.jl/refs/heads/main/DoodleBUGS/public/examples/kidney/model.json',
  },
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
