// Derive the Rust target, the embassy-stm32 chip feature and a normalised
// probe-rs chip name from the requested MCU part number.
//
// Examples:
//   STM32F103C8  -> thumbv7m-none-eabi,     stm32f103c8
//   STM32G474CE  -> thumbv7em-none-eabihf,  stm32g474ce
//   STM32H563ZI  -> thumbv8m.main-none-eabihf, stm32h563zi
//   STM32H745ZI  -> thumbv7em-none-eabihf,  stm32h745zi-cm7 (dual core, CM7)

let families = #{
    "F0": #{ target: "thumbv6m-none-eabi",        core: "Cortex-M0"  },
    "F1": #{ target: "thumbv7m-none-eabi",        core: "Cortex-M3"  },
    "F2": #{ target: "thumbv7m-none-eabi",        core: "Cortex-M3"  },
    "F3": #{ target: "thumbv7em-none-eabihf",     core: "Cortex-M4F" },
    "F4": #{ target: "thumbv7em-none-eabihf",     core: "Cortex-M4F" },
    "F7": #{ target: "thumbv7em-none-eabihf",     core: "Cortex-M7F" },
    "G0": #{ target: "thumbv6m-none-eabi",        core: "Cortex-M0+" },
    "G4": #{ target: "thumbv7em-none-eabihf",     core: "Cortex-M4F" },
    "H5": #{ target: "thumbv8m.main-none-eabihf", core: "Cortex-M33F" },
    "H7": #{ target: "thumbv7em-none-eabihf",     core: "Cortex-M7F" },
};

let mcu = variable::get("mcu").to_upper();
let part = mcu.sub_string(5, mcu.len() - 5); // strip the "STM32" prefix -> "G474CE"
let family = part.sub_string(0, 2);    // -> "G4"

let info = families.get(family);
if info == () {
    abort("Unsupported MCU: " + mcu + ". Only STM32 F/G/H parts supported by probe-rs are handled.");
}

// Dual-core H7 parts need an explicit core suffix in embassy-stm32.
let dual_core = ["H745", "H747", "H755", "H757"];
let is_dual_core = false;
for prefix in dual_core {
    if part.starts_with(prefix) {
        is_dual_core = true;
    }
}

let chip_feature = mcu.to_lower();
if is_dual_core {
    chip_feature += "-cm7";
}

// USART1 TX DMA binding used by the example in src/main.rs.
// embassy-stm32 names the peripheral singleton DMA1_CHx / GPDMA1_CHx on every
// family, but the DMA channel and its interrupt name differ between families
// (and, on F0, between chips).
let dma_peri = "DMA1_CH4";
let dma_irq = "DMA1_CHANNEL4";

if family == "F0" {
    dma_peri = "DMA1_CH2";
    dma_irq = "DMA1_CHANNEL2_3";
    if part.starts_with("F09") {
        // F091/F098 route their DMA IRQs through a combined vector.
        dma_irq = "DMA1_CH2_3_DMA2_CH1_2";
    }
} else if family == "F2" || family == "F4" || family == "F7" {
    dma_peri = "DMA2_CH7";
    dma_irq = "DMA2_STREAM7";
} else if family == "G0" {
    dma_peri = "DMA1_CH1";
    dma_irq = "DMA1_CHANNEL1";
} else if family == "H5" {
    dma_peri = "GPDMA1_CH4";
    dma_irq = "GPDMA1_CHANNEL4";
} else if family == "H7" {
    if part.starts_with("H7R") || part.starts_with("H7S") {
        dma_peri = "GPDMA1_CH4";
        dma_irq = "GPDMA1_CHANNEL4";
    } else {
        // Classic H7 (DMA1 streams via DMAMUX1).
        dma_peri = "DMA1_CH4";
        dma_irq = "DMA1_STREAM4";
    }
}

variable::set("dma_peri", dma_peri);
variable::set("dma_irq", dma_irq);

// Chips whose flash can be configured as single or dual bank (F4/F7/G0/G4
// parts, per stm32-metapac 21.0 metadata, which embassy-stm32 0.6 depends on).
// embassy-stm32's build script refuses to build these unless one of the
// 'single-bank' / 'dual-bank' features is selected; every one of them supports
// the single-bank layout, which also gives the linker the full flash size.
// Chips not listed here either have a fixed layout or are fixed dual-bank, and
// must NOT receive the 'single-bank' feature (the build script panics).
//
// This list is derived from `stm32-metapac`'s chip metadata. Regenerate it if
// the embassy-stm32 / stm32-metapac version changes.
let bank_configurable = [
    "stm32f427ag", "stm32f427ig", "stm32f427vg", "stm32f427zg", "stm32f429ag", "stm32f429bg",
    "stm32f429ig", "stm32f429ng", "stm32f429vg", "stm32f429zg", "stm32f437ig", "stm32f437vg",
    "stm32f437zg", "stm32f439bg", "stm32f439ig", "stm32f439ng", "stm32f439vg", "stm32f439zg",
    "stm32f469ag", "stm32f469bg", "stm32f469ig", "stm32f469ng", "stm32f469vg", "stm32f469zg",
    "stm32f479ag", "stm32f479bg", "stm32f479ig", "stm32f479ng", "stm32f479vg", "stm32f479zg",
    "stm32f765bg", "stm32f765bi", "stm32f765ig", "stm32f765ii", "stm32f765ng", "stm32f765ni",
    "stm32f765vg", "stm32f765vi", "stm32f765zg", "stm32f765zi", "stm32f767bg", "stm32f767bi",
    "stm32f767ig", "stm32f767ii", "stm32f767ng", "stm32f767ni", "stm32f767vg", "stm32f767vi",
    "stm32f767zg", "stm32f767zi", "stm32f768ai", "stm32f769ag", "stm32f769ai", "stm32f769bg",
    "stm32f769bi", "stm32f769ig", "stm32f769ii", "stm32f769ng", "stm32f769ni", "stm32f777bi",
    "stm32f777ii", "stm32f777ni", "stm32f777vi", "stm32f777zi", "stm32f778ai", "stm32f779ai",
    "stm32f779bi", "stm32f779ii", "stm32f779ni", "stm32g0b1cc", "stm32g0b1kc", "stm32g0b1mc",
    "stm32g0b1rc", "stm32g0b1vc", "stm32g0c1cc", "stm32g0c1kc", "stm32g0c1mc", "stm32g0c1rc",
    "stm32g0c1vc", "stm32g471cc", "stm32g471ce", "stm32g471mc", "stm32g471me", "stm32g471qc",
    "stm32g471qe", "stm32g471rc", "stm32g471re", "stm32g471vc", "stm32g471ve", "stm32g473cb",
    "stm32g473cc", "stm32g473ce", "stm32g473mb", "stm32g473mc", "stm32g473me", "stm32g473pb",
    "stm32g473pc", "stm32g473pe", "stm32g473qb", "stm32g473qc", "stm32g473qe", "stm32g473rb",
    "stm32g473rc", "stm32g473re", "stm32g473vb", "stm32g473vc", "stm32g473ve", "stm32g474cb",
    "stm32g474cc", "stm32g474ce", "stm32g474mb", "stm32g474mc", "stm32g474me", "stm32g474pb",
    "stm32g474pc", "stm32g474pe", "stm32g474qb", "stm32g474qc", "stm32g474qe", "stm32g474rb",
    "stm32g474rc", "stm32g474re", "stm32g474vb", "stm32g474vc", "stm32g474ve", "stm32g483ce",
    "stm32g483me", "stm32g483pe", "stm32g483qe", "stm32g483re", "stm32g483ve", "stm32g484ce",
    "stm32g484me", "stm32g484pe", "stm32g484qe", "stm32g484re", "stm32g484ve",
];

let use_single_bank = bank_configurable.contains(chip_feature);

variable::set("chip", mcu);
variable::set("chip_feature", chip_feature);
variable::set("rust_target", info.get("target"));
variable::set("core", info.get("core"));
variable::set("is_dual_core", is_dual_core);
variable::set("use_single_bank", use_single_bank);

// The CI workflow is opt-in. `file::delete` also works when the variable was
// never prompted ("advanced" is false), where an unprompted conditional
// placeholder resolves to an empty string.
let advanced = variable::get("advanced");
let ci = variable::get("ci");
if !advanced || ci == () || ci == "" || !ci {
    variable::set("ci", false);
    file::delete(".github");
}

// The conditional placeholders below only exist when "advanced" was enabled.
// An unprompted one resolves to an empty string, not (), so read them only
// when advanced is true.

// VS Code support (probe-rs launch config, build/flash tasks and
// rust-analyzer settings) is on by default; when it is switched off, drop the
// `.vscode/` directory before the files are copied.
let vscode_debug_enabled = true;
if advanced {
    vscode_debug_enabled = variable::get("vscode_debug");
}
variable::set("vscode_debug", vscode_debug_enabled);
if !vscode_debug_enabled {
    file::delete(".vscode");
}

// "memory_x": The user maintains memory.x themselves: keep the
// "memory-x" feature off and leave any existing memory.x in 
// the project alone. Otherwise rely on embassy's generated script.
let use_memory_x = false;
if advanced {
    use_memory_x = variable::get("memory_x");
}
variable::set("use_memory_x", use_memory_x);
if !use_memory_x {
    file::delete("memory.x");
}

// "caching": Whether to enable sccache caching for the build.
let caching = variable::get("caching");
if !advanced || caching == () || caching == "" || !caching {
    variable::set("caching", false);
}