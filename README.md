# FPGA Sensor Monitoring SoC

A multi-sensor acquisition and threshold monitoring system implemented in Verilog, targeting the Nexys A7 / Basys3 FPGA board (100 MHz clock, LVCMOS33 I/O). The design reads four sensor channels through a multiplexer, smooths the data via averaging, buffers it in a FIFO, and drives dual 7-segment displays alongside an RGB LED that indicates threshold status.

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Module Reference](#module-reference)
   - [seven_segment](#1-seven_segment)
   - [mux4x1](#2-mux4x1)
   - [adc_controller](#3-adc_controller)
   - [processing_unit](#4-processing_unit)
   - [fifo_buffer](#5-fifo_buffer)
   - [control_fsm](#6-control_fsm)
   - [output_rgb](#7-output_rgb)
   - [top_module](#8-top_module-top-level)
3. [Pin Constraints](#pin-constraints)
4. [How It Works — End-to-End](#how-it-works--end-to-end)
5. [Sensor Channels & Thresholds](#sensor-channels--thresholds)
6. [RGB LED Behaviour](#rgb-led-behaviour)
7. [Display Layout](#display-layout)
8. [RTL to GDS II Flow](#rtl-to-gds-ii-flow)
9. [Build & Flash](#build--flash)

---

## System Architecture

```
[4 Sensors]
  s0 (XADC temp) ──┐
  s1 (counter)  ───┤
  s2 (counter)  ───┤──► [mux4x1] ──► [adc_controller] ──► [processing_unit]
  s3 (counter)  ───┘         ▲                                      │
                              │                                      ▼
                           sw[1:0]                           [fifo_buffer] ◄── [control_fsm]
                                                                    │
                                                    ┌───────────────┼───────────────┐
                                                    ▼               ▼               ▼
                                               [output_rgb]  [BCD convert]  [seven_segment x2]
                                                  RGB1          D0/D1 SEG       D0/D1 AN
```

---

## Module Reference

---

### 1. `seven_segment`

**File:** `top_module.v` (sub-module)

Combinational BCD-to-7-segment decoder. Converts a 4-bit decimal digit (0–9) into active-low segment drive signals.

**Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `digit` | Input | 4 | BCD digit (0–9) |
| `seg` | Output | 7 | Segment outputs `{g,f,e,d,c,b,a}`, active-low |

**Segment Encoding (active-low)**

| Digit | seg[6:0] |
|-------|----------|
| 0 | `1000000` |
| 1 | `1111001` |
| 2 | `0100100` |
| 3 | `0110000` |
| 4 | `0011001` |
| 5 | `0010010` |
| 6 | `0000010` |
| 7 | `1111000` |
| 8 | `0000000` |
| 9 | `0010000` |

---

### 2. `mux4x1`

**File:** `top_module.v` (sub-module)

4-to-1 multiplexer. Selects one of four 12-bit sensor inputs based on a 2-bit select signal, routed directly from the board switches.

**Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `sensor0` | Input | 12 | Channel 0 — XADC temperature |
| `sensor1` | Input | 12 | Channel 1 — Simulated sensor |
| `sensor2` | Input | 12 | Channel 2 — Simulated sensor |
| `sensor3` | Input | 12 | Channel 3 — Simulated sensor |
| `sel` | Input | 2 | Channel select (= `sw[1:0]`) |
| `mux_out` | Output | 12 | Selected sensor value |

**Truth Table**

| sel | Output |
|-----|--------|
| `2'b00` | sensor0 |
| `2'b01` | sensor1 |
| `2'b10` | sensor2 |
| `2'b11` | sensor3 |

---

### 3. `adc_controller`

**File:** `top_module.v` (sub-module)

Synchronous sample-and-hold register. Captures the mux output into `adc_data` on every `sample_tick` pulse. Acts as the interface between the mux output and downstream processing.

**Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock (100 MHz) |
| `sample_tick` | Input | 1 | 1-cycle pulse at ~10 Hz sample rate |
| `mux_out` | Input | 12 | Data from mux |
| `adc_data` | Output reg | 12 | Latched sample |

**Timing:** Samples once every 10 million clock cycles (~100 ms / 10 Hz).

---

### 4. `processing_unit`

**File:** `top_module.v` (sub-module)

Moving-average filter (2-sample). Averages the current ADC sample with the previous sample to reduce noise.

**Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `sample_tick` | Input | 1 | Sample enable |
| `adc_data` | Input | 12 | Raw sample from ADC controller |
| `proc_data` | Output reg | 12 | Averaged (smoothed) output |

**Algorithm**

```
proc_data = (adc_data + prev) >> 1
prev       = adc_data
```

Uses a 13-bit intermediate `sum` to prevent overflow before the right shift.

---

### 5. `fifo_buffer`

**File:** `top_module.v` (sub-module)

16-entry × 12-bit synchronous FIFO with full/empty status flags. Decouples the processing pipeline from the display stage.

**Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `sample_tick` | Input | 1 | Gate for all FIFO operations |
| `wr_en` | Input | 1 | Write enable |
| `rd_en` | Input | 1 | Read enable |
| `din` | Input | 12 | Write data |
| `dout` | Output reg | 12 | Read data |
| `full` | Output | 1 | FIFO full flag |
| `empty` | Output | 1 | FIFO empty flag |

**Parameters**

| Parameter | Value |
|-----------|-------|
| Depth | 16 entries |
| Data width | 12 bits |
| Pointer width | 4 bits |

**Behaviour:** Write and read pointers wrap around automatically. Count is updated in the same clock cycle as the write/read operation, gated by `sample_tick`.

---

### 6. `control_fsm`

**File:** `top_module.v` (sub-module)

2-state FSM that alternates FIFO write and read enables every sample tick. Ensures data is written before it is read in a ping-pong fashion.

**Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `sample_tick` | Input | 1 | State advance enable |
| `wr_en` | Output reg | 1 | FIFO write enable |
| `rd_en` | Output reg | 1 | FIFO read enable |

**State Diagram**

```
State 0 → wr_en=1, rd_en=0 → State 1
State 1 → wr_en=0, rd_en=1 → State 0
```

Transitions occur only on `sample_tick` pulses.

---

### 7. `output_rgb`

**File:** `top_module.v` (sub-module)

RGB LED driver with threshold comparison and 5 Hz blinking for above-threshold events.

**Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock (100 MHz) |
| `data` | Input | 12 | Current FIFO output value |
| `threshold_value` | Input | 12 | Per-channel threshold |
| `RGB1` | Output reg | 3 | `{R, G, B}` active-low RGB LED |

**Behaviour**

| Condition | LED Colour | RGB1 value |
|-----------|------------|------------|
| `data < threshold` | Green | `3'b011` |
| `data == threshold` | Yellow (R+G) | `3'b010` |
| `data > threshold` | Red blinking | `3'b110` / `3'b111` |

Blink rate: toggles every 5,000,000 cycles = **10 Hz** toggle → **5 Hz** visible blink at 100 MHz.

---

### 8. `top_module` (Top Level)

**File:** `top_module.v`

Instantiates all sub-modules and handles: clock divider (sample tick), XADC IP core integration, real-temperature conversion, simulated sensor counters, threshold selection, BCD conversion, and display multiplexing.

**Top-Level Ports**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | 100 MHz system clock (pin F14) |
| `sw` | Input | 2 | Channel select switches |
| `RGB1` | Output | 3 | RGB LED |
| `D0_SEG` | Output | 7 | Left display segments (threshold) |
| `D0_AN` | Output reg | 4 | Left display anodes |
| `D1_SEG` | Output | 7 | Right display segments (sensor value) |
| `D1_AN` | Output reg | 4 | Right display anodes |

**Internal Clock Divider**

The sample tick is generated by a 24-bit counter:

```
Sample period = 10,000,000 cycles × (1 / 100 MHz) = 100 ms  →  10 Hz
```

**XADC Integration**

The on-chip XADC (`xadc_wiz_0`) reads the die temperature sensor (channel `5'h00`). Raw 12-bit output is converted to Celsius:

```
temp_°C = ((raw × 504) / 4096) − 273
```

**Display Refresh**

The 4-digit display is refreshed using a 16-bit counter with a 50,000-cycle period per digit (~500 Hz refresh rate), well above the persistence-of-vision threshold.

---

## Pin Constraints

### Clock

| Signal | Pin | Standard |
|--------|-----|----------|
| `clk` | F14 | LVCMOS33 |

### Switches

| Signal | Pin | Standard |
|--------|-----|----------|
| `sw[0]` | V2 | LVCMOS33 |
| `sw[1]` | U2 | LVCMOS33 |

### RGB LED

| Signal | Pin | Standard | Colour |
|--------|-----|----------|--------|
| `RGB1[0]` | U3 | LVCMOS33 | Red |
| `RGB1[1]` | V3 | LVCMOS33 | Green |
| `RGB1[2]` | V5 | LVCMOS33 | Blue |

### Left 7-Segment Display (D0) — Threshold Value

| Signal | Pin | Standard |
|--------|-----|----------|
| `D0_AN[0]` | D5 | LVCMOS33 |
| `D0_AN[1]` | C4 | LVCMOS33 |
| `D0_AN[2]` | C7 | LVCMOS33 |
| `D0_AN[3]` | A8 | LVCMOS33 |
| `D0_SEG[0]` | D7 | LVCMOS33 |
| `D0_SEG[1]` | C5 | LVCMOS33 |
| `D0_SEG[2]` | A5 | LVCMOS33 |
| `D0_SEG[3]` | B7 | LVCMOS33 |
| `D0_SEG[4]` | A7 | LVCMOS33 |
| `D0_SEG[5]` | D6 | LVCMOS33 |
| `D0_SEG[6]` | B5 | LVCMOS33 |

### Right 7-Segment Display (D1) — Processed Sensor Value

| Signal | Pin | Standard |
|--------|-----|----------|
| `D1_AN[0]` | H3 | LVCMOS33 |
| `D1_AN[1]` | J4 | LVCMOS33 |
| `D1_AN[2]` | F3 | LVCMOS33 |
| `D1_AN[3]` | E4 | LVCMOS33 |
| `D1_SEG[0]` | F4 | LVCMOS33 |
| `D1_SEG[1]` | J3 | LVCMOS33 |
| `D1_SEG[2]` | D2 | LVCMOS33 |
| `D1_SEG[3]` | C2 | LVCMOS33 |
| `D1_SEG[4]` | B1 | LVCMOS33 |
| `D1_SEG[5]` | H4 | LVCMOS33 |
| `D1_SEG[6]` | D1 | LVCMOS33 |

---

## How It Works — End-to-End

```
1. Every 100 ms, sample_tick fires for one clock cycle.

2. mux4x1 selects one of four sensor values based on sw[1:0].

3. adc_controller latches the selected value into adc_data.

4. processing_unit averages adc_data with the previous sample → proc_data.

5. control_fsm alternates:
      Tick N   → wr_en=1  (write proc_data into FIFO)
      Tick N+1 → rd_en=1  (read from FIFO → fifo_out)

6. output_rgb compares fifo_out against threshold_value:
      Below  → Green LED
      Equal  → Yellow LED
      Above  → Red blinking LED (5 Hz)

7. BCD dividers split fifo_out and threshold_value into
   thousands/hundreds/tens/ones digits.

8. Display refresh multiplexer cycles through all 4 digit positions
   at ~500 Hz, driving D0 (threshold) and D1 (sensor value) simultaneously.
```

---

## Sensor Channels & Thresholds

| sw[1:0] | Channel | Source | Threshold |
|---------|---------|--------|-----------|
| `00` | 0 | XADC die temperature (°C) | 38 |
| `01` | 1 | Simulated counter (1000–4000, step +1) | 3000 |
| `10` | 2 | Simulated counter (2500–4000, step +2) | 3000 |
| `11` | 3 | Simulated counter (3500–4000, step +3) | 3000 |

Simulated counters wrap back to their start values when they reach 4000, incrementing every sample tick (~10 Hz).

---

## RGB LED Behaviour

| LED Colour | Meaning |
|------------|---------|
| 🟢 Green | Sensor value is **below** threshold — normal |
| 🟡 Yellow | Sensor value **equals** threshold — at limit |
| 🔴 Red (blinking) | Sensor value is **above** threshold — alert |

---

## Display Layout

```
┌──────────────────────────────────────┐
│  D0 (Left 4 digits)                  │
│  Shows: Threshold value              │
│                                      │
│  D1 (Right 4 digits)                 │
│  Shows: Processed sensor value       │
└──────────────────────────────────────┘

Example with sw=00 (temperature channel, threshold=38, reading=37):
  D0: 0038   D1: 0037   LED: GREEN
```

---

## RTL to GDS II Flow

The design was taken through a full digital implementation flow using the **Cadence EDA toolchain** on a Linux workstation.

---

### Tool Chain

| Stage | Tool | Version |
|-------|------|---------|
| Logic Synthesis | Cadence Genus Synthesis Solution | 21.1 |
| Place & Route | Cadence Innovus Implementation System | 21.15 |

---

### Stage 1 — Logic Synthesis (Cadence Genus)

The Verilog RTL was synthesised using **Cadence Genus 21.1** targeting a standard-cell library.

**Synthesis results for `top_module`:**

| Metric | Value |
|--------|-------|
| Leaf Cells | 1035 |
| Nets | 1059 |
| I/O Terms | 29 |

The schematic view in Genus shows the fully elaborated netlist with all standard cells mapped and connections resolved across all sub-modules (mux4x1, adc_controller, processing_unit, fifo_buffer, control_fsm, output_rgb, seven_segment ×2).

<img width="1920" height="1020" alt="Screenshot 2026-05-26 110837" src="https://github.com/user-attachments/assets/522b8404-db90-4987-85b9-5400e7cfef38" />


---

### Stage 2 — Floorplan & Placement (Cadence Innovus)

The synthesised netlist was imported into **Cadence Innovus 21.15** for physical implementation.

- Die area defined and I/O pins assigned.
- Standard cells placed using Innovus global and detailed placement.
- Power mesh (VDD/VSS) routed across the floorplan.
- Layers visible post-placement: **Poly(0), Cont(0), Metal1(1), Via1(1), Metal2(2)**.

The post-placement layout shows densely packed standard cell rows filling the floorplan with no routing yet applied.
<img width="1920" height="1020" alt="Screenshot 2026-05-27 091134" src="https://github.com/user-attachments/assets/248b409e-818b-440b-9101-549b3e624536" />


---

### Stage 3 — Routing (Cadence Innovus)

Global and detailed routing was completed within Innovus.

- All signal nets routed across **Metal1**, **Via1**, and **Metal2** layers.
- Power rings and stripes completed.
- The routed layout shows full metal connectivity with the characteristic multi-colour layer view (green = Metal1, red = Metal2, cyan = power rings).
<img width="1920" height="1020" alt="Screenshot 2026-05-27 091207" src="https://github.com/user-attachments/assets/224b61dc-4ec0-4652-b462-ff1d197d58c8" />


---

### Stage 4 — Verification (`verifyConnectivity`)

Post-route connectivity verification was run inside Innovus:

```
******** End: VERIFY CONNECTIVITY ********
  Verification Complete : 0 Viols.  0 Wrngs.
  (CPU Time: 0:00:00.0  MEM: 0.000M)
```

**Result: 0 Violations, 0 Warnings** — the routed netlist is fully connected and matches the synthesised gate-level netlist.

> Note: `IMPVFC-97` warnings were raised for unassigned I/O pins (`D1_SEG[4]`, `D1_SEG[1]`, `led[3]`) during `verifyConnectivity`. These are expected for signals not mapped to physical I/O cells in the standard-cell flow and do not affect internal logic connectivity.
<img width="1920" height="1020" alt="Screenshot 2026-05-29 150419" src="https://github.com/user-attachments/assets/96083921-90d0-486a-bdd9-322944d17c99" />


---

### Flow Summary

```
Verilog RTL (top_module.v)
        │
        ▼
[Cadence Genus 21.1] — Logic Synthesis
        │  1035 leaf cells, 1059 nets
        ▼
Gate-level Netlist (.v) + SDC
        │
        ▼
[Cadence Innovus 21.15] — Floorplan
        │  Die area, I/O assignment, power mesh
        ▼
[Cadence Innovus 21.15] — Place
        │  Global + detailed placement
        ▼
[Cadence Innovus 21.15] — Route
        │  Global + detailed routing (Metal1/Via1/Metal2)
        ▼
[Cadence Innovus 21.15] — verifyConnectivity
        │  0 Violations, 0 Warnings
        ▼
GDS II (final layout)
```

---

## Build & Flash

### Prerequisites

- Xilinx Vivado 2020.x or later
- Target board: Nexys A7 / Basys3 (100 MHz oscillator)
- XADC Wizard IP (`xadc_wiz_0`) generated with default temperature sensor settings

### Steps

```bash
# 1. Open Vivado and create a new project
#    Add top_module.v as the design source

# 2. Generate XADC IP
#    IP Catalog → XADC Wizard → Component name: xadc_wiz_0
#    Mode: Continuous, Channel: Temperature (channel 0)

# 3. Add constraints file
#    Add the provided .xdc file to the project

# 4. Run Synthesis → Implementation → Generate Bitstream

# 5. Program the device
#    Open Hardware Manager → Program Device → select .bit file
```

### Simulation

Each sub-module can be simulated independently. Apply `sample_tick` pulses to drive the pipeline. The `processing_unit` requires two ticks before producing valid averaged output (one tick to load `prev`).
