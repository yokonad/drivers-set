# drivers-set

Busca e instala los drivers faltantes o recomendados de Windows con **una sola línea** en PowerShell.

Usa **Windows Update** como fuente: solo drivers **WHQL** (certificados y testeados por Microsoft), los más estables — pensados para no romper Windows.

## Uso

Abre **PowerShell** y pega:

```powershell
irm https://raw.githubusercontent.com/yokonad/drivers-set/main/drivers-set.ps1 | iex
```

El script:

1. Se **auto-eleva** a Administrador (te pedirá permiso con un cuadro UAC).
2. Muestra un **inventario de tu equipo**: procesador (Intel/AMD), gráfica (NVIDIA/AMD/Intel), pantalla, RAM, placa base, red y audio.
3. **Escanea** los dispositivos con problemas o sin driver.
4. **Consulta Windows Update**, incluyendo drivers **opcionales**, por los disponibles (solo WHQL/firmados).
5. Te muestra la lista. **Pulsa ENTER para instalar TODOS**, o escribe números (`1,3`) para elegir, o `no` para salir.
6. **Instala** los elegidos y avisa si hay que reiniciar.

## Importante

- Funciona en **cualquier PC con Windows** sin cambiar nada: detecta el hardware real de cada equipo e instala solo los drivers que esa máquina necesita.
- La URL del comando apunta siempre a este repositorio (es de dónde se descarga el script); no depende de la PC donde se ejecute.
- Requiere conexión a internet y el servicio **Windows Update** activo.
- No descarga drivers de sitios de terceros: todo proviene del catálogo oficial de Microsoft.

## ¿Por qué WHQL y no "el más nuevo" de cada fabricante?

Los drivers WHQL pasaron las pruebas de certificación de Microsoft y están firmados,
así que son los más estables. Los drivers beta directos de cada fabricante a veces son
más nuevos pero pueden causar inestabilidad. Esta herramienta prioriza **que no rompa Windows**.
