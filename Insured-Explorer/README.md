# Travel Insurance Automation Smart Contract

## Overview

This smart contract automates travel insurance policies, claims processing, and payouts on the Stacks blockchain. It provides a decentralized platform for purchasing travel insurance, submitting claims, and receiving automated payouts for covered incidents.

## Features

### Policy Management
- Purchase travel insurance policies with customizable coverage amounts
- Three policy types: Basic, Comprehensive, and Premium
- Automatic premium calculation based on coverage, trip duration, and policy type
- Policy cancellation with partial refunds (50% refund if cancelled before trip starts)

### Claims Processing
- Submit claims for various travel-related incidents
- Manual claim processing by authorized processors
- Automatic payouts for flight delay claims with verifiable data
- 30-day claim window after trip ends

### Coverage Types
- Trip Cancellation
- Flight Delays
- Baggage Loss
- Medical Emergencies
- Trip Interruption

## Policy Types and Coverage

### Basic Policy (Type 1)
- Trip Cancellation: 50% of coverage amount
- Flight Delay: 10% of coverage amount
- Baggage Loss: 20% of coverage amount
- Medical Emergency: 80% of coverage amount
- Trip Interruption: 40% of coverage amount
- Premium Rate: 0.05% of coverage amount

### Comprehensive Policy (Type 2)
- Trip Cancellation: 75% of coverage amount
- Flight Delay: 20% of coverage amount
- Baggage Loss: 30% of coverage amount
- Medical Emergency: 100% of coverage amount
- Trip Interruption: 60% of coverage amount
- Premium Rate: 0.075% of coverage amount

### Premium Policy (Type 3)
- Trip Cancellation: 100% of coverage amount
- Flight Delay: 30% of coverage amount
- Baggage Loss: 50% of coverage amount
- Medical Emergency: 100% of coverage amount
- Trip Interruption: 80% of coverage amount
- Premium Rate: 0.1% of coverage amount

## Contract Limits

- **Minimum Premium**: 0.1 STX
- **Maximum Coverage**: 100,000 STX
- **Minimum Trip Duration**: 1 day
- **Maximum Trip Duration**: 365 days
- **Claim Window**: 30 days after trip ends
- **Maximum Policies per User**: 50
- **Maximum Claims per Policy**: 10

## Public Functions

### Policy Functions

#### `purchase-policy`
Purchase a new travel insurance policy.

**Parameters:**
- `coverage-amount` (uint): Total coverage amount in microSTX
- `trip-start` (uint): Trip start timestamp
- `trip-end` (uint): Trip end timestamp
- `destination` (string-ascii 100): Trip destination
- `policy-type` (uint): Policy type (1=Basic, 2=Comprehensive, 3=Premium)

**Returns:** Policy ID

#### `cancel-policy`
Cancel an active policy before the trip starts (50% refund).

**Parameters:**
- `policy-id` (uint): ID of the policy to cancel

**Returns:** Refund amount

### Claim Functions

#### `submit-claim`
Submit an insurance claim for a covered incident.

**Parameters:**
- `policy-id` (uint): Associated policy ID
- `claim-type` (uint): Type of claim (1-5)
- `amount` (uint): Claim amount in microSTX
- `description` (string-ascii 500): Claim description
- `evidence-hash` (string-ascii 64): Hash of supporting evidence

**Returns:** Claim ID

#### `process-claim`
Process a pending claim (approve or reject). Only available to authorized processors.

**Parameters:**
- `claim-id` (uint): ID of the claim to process
- `approve` (bool): Whether to approve the claim

**Returns:** Approval status

#### `pay-claim`
Pay out an approved claim.

**Parameters:**
- `claim-id` (uint): ID of the approved claim to pay

**Returns:** Payout amount

#### `automatic-payout`
Automatically process and pay flight delay claims.

**Parameters:**
- `claim-id` (uint): ID of the flight delay claim

**Returns:** Payout amount

### Administrative Functions

#### `add-funds`
Add funds to the contract balance. Only available to contract owner.

**Parameters:**
- `amount` (uint): Amount to add in microSTX

#### `authorize-processor`
Authorize a new claim processor. Only available to contract owner.

**Parameters:**
- `processor` (principal): Address of the processor to authorize

#### `revoke-processor`
Revoke processor authorization. Only available to contract owner.

**Parameters:**
- `processor` (principal): Address of the processor to revoke

## Read-Only Functions

### Information Queries

#### `get-policy`
Retrieve policy details by ID.

#### `get-claim`
Retrieve claim details by ID.

#### `get-user-policies`
Get all policy IDs for a specific user.

#### `get-policy-claims`
Get all claim IDs for a specific policy.

#### `get-contract-stats`
Get contract statistics including total policies, claims, premiums, and balance.

#### `get-coverage-multipliers`
Get coverage percentages for each policy type.

#### `quote-premium`
Calculate premium for given parameters without purchasing.

#### `is-authorized-processor`
Check if an address is an authorized claim processor.

## Error Codes

- `u100`: Unauthorized access
- `u101`: Invalid policy
- `u102`: Policy expired
- `u103`: Insufficient funds
- `u104`: Claim already exists
- `u105`: Invalid claim
- `u106`: Claim submission expired
- `u107`: Already processed
- `u108`: Invalid amount
- `u109`: Policy not active
- `u110`: Invalid dates

## Usage Example

### Purchase a Policy
```clarity
(contract-call? .travel-insurance purchase-policy
  u10000000000  ;; 10,000 STX coverage
  u1671840000   ;; Trip start timestamp
  u1672444800   ;; Trip end timestamp
  "Paris, France"
  u2)           ;; Comprehensive policy
```

### Submit a Claim
```clarity
(contract-call? .travel-insurance submit-claim
  u1            ;; Policy ID
  u2            ;; Flight delay claim
  u500000000    ;; 500 STX claim amount
  "Flight delayed 4 hours due to weather"
  "abc123hash") ;; Evidence hash
```

### Get Premium Quote
```clarity
(contract-call? .travel-insurance quote-premium
  u10000000000  ;; Coverage amount
  u1671840000   ;; Trip start
  u1672444800   ;; Trip end
  u1)           ;; Basic policy
```

## Security Features

- Owner-only administrative functions
- Authorization system for claim processors
- Validation of all inputs and timestamps
- Protection against double-spending and invalid claims
- Time-based restrictions on claims and cancellations

## Deployment Requirements

- Stacks blockchain testnet or mainnet
- Clarity smart contract runtime
- STX tokens for testing and operation