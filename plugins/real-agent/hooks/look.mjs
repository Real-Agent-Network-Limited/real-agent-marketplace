// The Code tab's look: Real Agent's ink and paper, with its lime as the accent. Every colour is one of brand/real-agent/palette.css, and __tests__/plugin.test.mjs holds it to that.
export const LOOK = {
  label: 'Real Agent',
  roles: { accent: '#4D6100' },
  light: {
    gray: {
      anchors: {
        'surface-0': '#FAFAF8',
        'text-primary': '#0E0E0E',
        'text-secondary': '#6B6B66',
        'text-muted': '#6B6B66',
      },
    },
  },
  dark: {
    roles: { accent: '#CCFF00' },
    gray: {
      anchors: {
        'surface-0': '#0E0E0E',
        'surface-1': '#1C1C1A',
        'surface-2': '#1C1C1A',
        'surface-3': '#1C1C1A',
        'text-primary': '#FAFAF8',
        'text-secondary': '#A6A69E',
        'text-muted': '#A6A69E',
      },
    },
  },
}

export const HOME_TEXT = 'What is outstanding?'
