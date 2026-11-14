#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_stm32::{
    bind_interrupts,
    mode::Async,
    usart::{Config, UartTx},
};
use embassy_sync::{blocking_mutex::raw::CriticalSectionRawMutex, channel::Channel};
use embassy_time::{Duration, Timer};

use {defmt_rtt as _, panic_probe as _};
{%- if is_dual_core %}

// Dual-core parts (e.g. STM32H745) have no plain `embassy_stm32::init`.
// The Cortex-M7 runs the primary initialisation and shares the RCC state
// with the other core through this static.
use core::mem::MaybeUninit;
use embassy_stm32::{init_primary, SharedData};

static SHARED_DATA: MaybeUninit<SharedData> = MaybeUninit::uninit();
{%- endif %}

// NOTE: USART1 TX is on PA9. The DMA channel and IRQ below are picked per
// family by the template (F0: DMA1_CH2, F2/F4/F7: DMA2_CH7, G0: DMA1_CH1,
// F1/F3/G4: DMA1_CH4, H5/H7RS: GPDMA1_CH4, H7: DMA1_CH4/DMA1_STREAM4).
// A few parts do not route USART1 TX to PA9 (e.g. STM32F410T8, STM32H523HE);
// for those, change the pin and DMA channel to match the reference manual.
bind_interrupts!(struct Irqs {
    {{ dma_irq }} => embassy_stm32::dma::InterruptHandler<embassy_stm32::peripherals::{{ dma_peri }}>;
});

// Simple in-firmware message queue shared between the tasks.
static EVENTS: Channel<CriticalSectionRawMutex, u8, 8> = Channel::new();

#[embassy_executor::main]
async fn main(spawner: Spawner) {
{%- if is_dual_core %}
    let p = init_primary(Default::default(), &SHARED_DATA);
{%- else %}
    let p = embassy_stm32::init(Default::default());
{%- endif %}

    info!("{{project-name}} running on {{ chip }} ({{ core }})");

    // USART1 TX @ 115200, transmitted through DMA.
    let mut config = Config::default();
    config.baudrate = 115_200;
    let dma = p.{{ dma_peri }};
    let uart = UartTx::new(p.USART1, p.PA9, dma, Irqs, config).expect("UART initialization failed");

    spawner.spawn(uart_task(uart).unwrap());

    // Consume the messages produced by the background task.
    loop {
        let event = EVENTS.receive().await;
        info!("received: {}", event);
    }
}

#[embassy_executor::task]
async fn uart_task(mut uart: UartTx<'static, Async>) {
    let mut ticks: u8 = 0;

    loop {
        uart.write(b"UART alive\r\n").await.unwrap();

        EVENTS.send(ticks).await;
        ticks = ticks.wrapping_add(1);

        Timer::after(Duration::from_secs(1)).await;
    }
}
