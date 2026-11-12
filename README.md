# PCA9555 I2C GPIO Expander Study

## Introduction
The PCA9555 is a 16-bit I/O expander controlled through the I2C protocol.

## Architecture
- Top Module: pca9555.v
- I2C Controller: i2c_slave.v
- Register Block: reg_file.v
- Interrupt Logic: int_logic.v
- I/O Interface: io_ports.v

## Learning Outcomes
- Understanding I2C communication
- RTL organization
- State machine operation
- Interrupt handling

## Verification Summary
- START condition observed
- STOP condition observed
- State transitions analyzed
- Interrupt behavior verified
