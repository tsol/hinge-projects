import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { mountHinge } from 'hinge'
import 'hinge/style.css'
import './index.css'
import App from './App.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

mountHinge('body')
