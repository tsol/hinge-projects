<script setup lang="ts">
import { Hinge } from 'hinge/component'
import 'hinge/style.css'
</script>

<template>
  <div class="app">
    <header>
      <h1>Vite + Vue + Hinge</h1>
      <p>Edit <code>src/App.vue</code> and save to test HMR.</p>
    </header>
    <main>
      <p>Use the cog button to queue agent tasks.</p>
    </main>
    <Hinge />
  </div>
</template>

<style scoped>
.app {
  max-width: 720px;
  margin: 0 auto;
  padding: 2rem 1.5rem;
  font-family: system-ui, sans-serif;
}

header h1 {
  margin: 0 0 0.5rem;
}
</style>
