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

// Adjust the DMA, IRQ and pin names to match your chip's
// reference manual / embassy-stm32 examples.
bind_interrupts!(struct Irqs {
    DMA1_CHANNEL4 => embassy_stm32::dma::InterruptHandler<embassy_stm32::peripherals::DMA1_CH4>;
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
    let uart =
        UartTx::new(p.USART1, p.PA9, p.DMA1_CH4, Irqs, config).expect("UART initialization failed");

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
