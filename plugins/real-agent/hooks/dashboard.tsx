import type { Register } from 'claude-code'

import { makeColors } from './make-colors.js'
import { HOME_TEXT, LOOK } from './look.mjs'

const { theme } = makeColors(LOOK)

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // A host that draws no theme, such as `claude plugin test`, has no $.theme.
    try {
      await $.theme.set({ colors: theme })
    } catch {}

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) {
      return next(e)
    }
    const { Box, Button } = $.ui.resolve(e)

    // The app's own button, as measured in the Claude desktop app: rounded, one line tall, and a label the app makes
    // readable in light and dark. A colour of our own around it left the label unreadable in one mode or the other.
    return (
      <Box flexDirection="row">
        <Button key="dashboard" label="Dashboard" onPress={() => void $.prompt.submit({ text: HOME_TEXT, asUser: true })} />
      </Box>
    )
  })
}
