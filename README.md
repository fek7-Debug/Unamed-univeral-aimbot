# 🌟 unamed universal aimbot — Roblox Luau

[ESPAÑOL]
Un script de interfaz premium, motores de renderizado avanzados y asistencia de combate optimizado al 100% para ejecutores de **Android móviles (como Delta)**. Diseñado de forma completamente programática, este Hub es **100% Universal** y compatible con cualquier juego de Roblox utilizando funciones nativas del motor del juego.

[ENGLISH]
A premium interface script, advanced rendering engines, and combat assistance 100% optimized for **mobile Android executors (such as Delta)**. Built completely programmatically, this Hub is **100% Universal** and compatible with any Roblox game using native game engine functions.

---

## ✨ Características Principales / Features

### 🎯 1. Aimbot Suave & Wallcheck Físico / Smooth Aimbot & Physical Wallcheck
* **Fijación Lerp Inteligente (ES):** Interpolación de cámara fluida y adaptable a la tasa de refresco de dispositivos móviles.
* **Smart Lerp Lock (EN):** Smooth camera interpolation adapted to mobile device refresh rates.
* **Filtros Avanzados (ES):** Círculo de FOV interactivo (ajustable en radio y color), selector de articulación objetivo (`Head` o `HumanoidRootPart`).
* **Advanced Filters (EN):** Interactive FOV circle (adjustable radius & color) and target bone selector (`Head` or `HumanoidRootPart`).
* **Wallcheck Ultra-Eficiente (ES):** Comprobación de visibilidad directa mediante un único objeto `RaycastParams` cacheado para no generar lag ni calentar el móvil.
* **Ultra-Efficient Wallcheck (EN):** Direct visibility check via a single cached `RaycastParams` object to avoid lag or overheating.

### 👁️ 2. Motor de ESP 2D Avanzado / Advanced 2D ESP Engine (Static Cache)
* **Cero Overhead / Lag (ES):** Renderizado optimizado mediante `Drawing.new` estático para evitar caídas de FPS en pantallas táctiles.
* **Zero Overhead / Lag (EN):** Optimized rendering via static `Drawing.new` allocation to prevent FPS drops on touch screens.
* **Proyección 2D/3D Precisa (ES):** Cajas adaptables basadas en el Bounding Box real del personaje de los enemigos.
* **Accurate 2D/3D Projection (EN):** Adaptive boxes based on the actual 3D character Bounding Box.
* **Visuales Completos (ES):** Box ESP, Skeleton ESP, Barra de salud proporcional, Name ESP, Indicador de Studs (distancia) y Off-Screen Pointer (flechas indicadoras rojas).
* **Full Visuals (EN):** Box ESP, Skeleton ESP, proportional Health Bar, Name ESP, Studs Indicator (distance), and Off-Screen Pointer (red arrow indicators).

### 👥 3. Team Check con Sincronización / Team Check Sync (Spectator Proof)
* **A prueba de Espectadores (ES):** Hilo asincrónico que valida los equipos cada 1.5 segundos. El ESP se reactiva automáticamente si estás solo o espectando.
* **Spectator Safe (EN):** Background thread that validates teams every 1.5s. The ESP automatically re-activates if you are alone or spectating.
* **Notificaciones Estéticas (ES):** Cartel flotante animado con desvanecimiento alfa (`TweenService`) en **Verde** ("Team Check Active") o **Rojo** ("not team found").
* **Aesthetic Notifications (EN):** Floating animated alert with alpha fade out in **Green** ("Team Check Active") or **Red** ("not team found").

### 🏃 4. Módulo Player Universal / Universal Player Module (Movement & Physics)
* **WalkSpeed & JumpPower Hack (ES):** Modificadores continuos con sliders integrados para alterar la velocidad y salto de forma segura.
* **WalkSpeed & JumpPower Hack (EN):** Continuous modifiers with integrated sliders to alter speed and jump power safely.
* **Infinite Jump (ES):** Sistema de salto táctil infinito para elevarte en el aire presionando el botón de salto repetidamente.
* **Infinite Jump (EN):** Infinite touch-based jump system to lift yourself into the air by tapping the jump button repeatedly.
* **Universal Noclip (ES):** Opción binaria (Toggle) ligera que elimina las colisiones corporales para atravesar estructuras sin lag de físicas.
* **Universal Noclip (EN):** Lightweight binary option (Toggle) that disables body collisions to clip through walls seamlessly.

---

## 🎨 5. Interfaz de Usuario / UI Design
* **ES:** Diseño oscuro moderno con bordes redondeados (`UICorner`), degradados dinámicos (`UIGradient`) y un FAB Flotante deslizable por tacto con estrella (`★`) para abrir/cerrar el menú.
* **EN:** Modern dark theme with rounded corners (`UICorner`), dynamic gradients (`UIGradient`), and a touch-draggable Floating FAB with a star symbol (`★`) to toggle menu visibility.

---

## 🚀 Cómo Ejecutar / How to Use

Copia y pega el siguiente cargador en la barra de ejecución de tu exploit móvil / Copy and paste the following loader into your mobile exploit:

```lua
-- [[ UNAMED UNIVERSAL AIMBOT — LOADSTRING ]] --
loadstring(game:HttpGet("https://githubusercontent.com"))()
```

---

## 🛡️ Optimización Móvil / Performance & Optimization
* **ES:** Este script fue desarrollado con el objetivo de mantener los **FPS estables** en dispositivos móviles Android de gama media y baja. Al evitar la creación masiva de tablas dentro de bucles calientes (`RenderStepped`) y reutilizar memoria, tu dispositivo no sufrirá lag por recolección de basura (*Garbage Collector pressure*).
* **EN:** This script was developed to maintain **stable FPS** on low and mid-range Android devices. By avoiding massive table allocation inside hot loops (`RenderStepped`) and recycling drawing objects, your device won't suffer from constant Garbage Collector spikes.
