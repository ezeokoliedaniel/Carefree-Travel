;; Travel Insurance Automation Smart Contract
;; This contract automates travel insurance policies, claims, and payouts

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_POLICY (err u101))
(define-constant ERR_POLICY_EXPIRED (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_CLAIM_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_CLAIM (err u105))
(define-constant ERR_CLAIM_EXPIRED (err u106))
(define-constant ERR_ALREADY_PROCESSED (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_POLICY_NOT_ACTIVE (err u109))
(define-constant ERR_INVALID_DATES (err u110))

;; Minimum and maximum values
(define-constant MIN_PREMIUM u100000) ;; 0.1 STX
(define-constant MAX_COVERAGE u100000000000) ;; 100,000 STX
(define-constant MIN_TRIP_DURATION u1) ;; 1 day
(define-constant MAX_TRIP_DURATION u365) ;; 1 year
(define-constant CLAIM_WINDOW u2592000) ;; 30 days in seconds

;; Policy status constants
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_EXPIRED u2)
(define-constant STATUS_CANCELLED u3)
(define-constant STATUS_CLAIMED u4)

;; Claim status constants
(define-constant CLAIM_PENDING u1)
(define-constant CLAIM_APPROVED u2)
(define-constant CLAIM_REJECTED u3)
(define-constant CLAIM_PAID u4)

;; Claim type constants
(define-constant CLAIM_TRIP_CANCELLATION u1)
(define-constant CLAIM_FLIGHT_DELAY u2)
(define-constant CLAIM_BAGGAGE_LOSS u3)
(define-constant CLAIM_MEDICAL_EMERGENCY u4)
(define-constant CLAIM_TRIP_INTERRUPTION u5)

;; Data Variables
(define-data-var policy-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var total-premiums uint u0)
(define-data-var total-claims-paid uint u0)
(define-data-var contract-balance uint u0)

;; Data Maps
(define-map policies
  { policy-id: uint }
  {
    policyholder: principal,
    premium: uint,
    coverage-amount: uint,
    trip-start: uint,
    trip-end: uint,
    destination: (string-ascii 100),
    status: uint,
    created-at: uint,
    policy-type: uint ;; 1=basic, 2=comprehensive, 3=premium
  }
)

(define-map claims
  { claim-id: uint }
  {
    policy-id: uint,
    claimant: principal,
    claim-type: uint,
    amount: uint,
    description: (string-ascii 500),
    evidence-hash: (string-ascii 64),
    status: uint,
    created-at: uint,
    processed-at: (optional uint),
    processor: (optional principal)
  }
)

(define-map user-policies
  { user: principal }
  { policy-ids: (list 50 uint) }
)

(define-map policy-claims
  { policy-id: uint }
  { claim-ids: (list 10 uint) }
)

(define-map coverage-multipliers
  { policy-type: uint }
  { 
    trip-cancellation: uint,
    flight-delay: uint,
    baggage-loss: uint,
    medical-emergency: uint,
    trip-interruption: uint
  }
)

;; Authorization map for claim processors
(define-map authorized-processors
  { processor: principal }
  { authorized: bool }
)

;; Initialize coverage multipliers (in basis points, 10000 = 100%)
(map-set coverage-multipliers { policy-type: u1 } ;; Basic
  {
    trip-cancellation: u5000,   ;; 50% of coverage
    flight-delay: u1000,        ;; 10% of coverage
    baggage-loss: u2000,        ;; 20% of coverage
    medical-emergency: u8000,   ;; 80% of coverage
    trip-interruption: u4000    ;; 40% of coverage
  }
)

(map-set coverage-multipliers { policy-type: u2 } ;; Comprehensive
  {
    trip-cancellation: u7500,   ;; 75% of coverage
    flight-delay: u2000,        ;; 20% of coverage
    baggage-loss: u3000,        ;; 30% of coverage
    medical-emergency: u10000,  ;; 100% of coverage
    trip-interruption: u6000    ;; 60% of coverage
  }
)

(map-set coverage-multipliers { policy-type: u3 } ;; Premium
  {
    trip-cancellation: u10000,  ;; 100% of coverage
    flight-delay: u3000,        ;; 30% of coverage
    baggage-loss: u5000,        ;; 50% of coverage
    medical-emergency: u10000,  ;; 100% of coverage
    trip-interruption: u8000    ;; 80% of coverage
  }
)

;; Private Functions

;; Calculate premium based on coverage, duration, and policy type
(define-private (calculate-premium (coverage uint) (duration uint) (policy-type uint))
  (let
    (
      (base-rate (if (is-eq policy-type u1) u50    ;; Basic: 0.05%
                 (if (is-eq policy-type u2) u75    ;; Comprehensive: 0.075%
                     u100)))                       ;; Premium: 0.1%
      (duration-factor (if (<= duration u7) u100   ;; 1 week: 100%
                      (if (<= duration u30) u150   ;; 1 month: 150%
                          u200)))                  ;; >1 month: 200%
    )
    (/ (* (* coverage base-rate) duration-factor) u1000000) ;; Normalize percentage
  )
)

;; Validate trip dates
(define-private (validate-trip-dates (trip-start uint) (trip-end uint))
  (let
    (
      (current-time (unwrap! (get-block-info? time (- block-height u1)) false))
      (trip-duration (- trip-end trip-start))
    )
    (and
      (> trip-start current-time)           ;; Trip must be in future
      (> trip-end trip-start)               ;; End after start
      (>= trip-duration (* MIN_TRIP_DURATION u86400)) ;; Min duration in seconds
      (<= trip-duration (* MAX_TRIP_DURATION u86400)) ;; Max duration in seconds
    )
  )
)

;; Calculate maximum claim amount for a claim type
(define-private (get-max-claim-amount (policy-id uint) (claim-type uint))
  (match (map-get? policies { policy-id: policy-id })
    policy-data
      (match (map-get? coverage-multipliers { policy-type: (get policy-type policy-data) })
        multipliers
          (let
            (
              (coverage (get coverage-amount policy-data))
              (multiplier (if (is-eq claim-type CLAIM_TRIP_CANCELLATION)
                            (get trip-cancellation multipliers)
                          (if (is-eq claim-type CLAIM_FLIGHT_DELAY)
                            (get flight-delay multipliers)
                          (if (is-eq claim-type CLAIM_BAGGAGE_LOSS)
                            (get baggage-loss multipliers)
                          (if (is-eq claim-type CLAIM_MEDICAL_EMERGENCY)
                            (get medical-emergency multipliers)
                            (get trip-interruption multipliers))))))
            )
            (some (/ (* coverage multiplier) u10000))
          )
        none
      )
    none
  )
)

;; Add policy to user's policy list
(define-private (add-policy-to-user (user principal) (policy-id uint))
  (let
    (
      (current-policies (default-to (list) (get policy-ids (map-get? user-policies { user: user }))))
    )
    (map-set user-policies
      { user: user }
      { policy-ids: (unwrap! (as-max-len? (append current-policies policy-id) u50) false) }
    )
  )
)

;; Add claim to policy's claim list
(define-private (add-claim-to-policy (policy-id uint) (claim-id uint))
  (let
    (
      (current-claims (default-to (list) (get claim-ids (map-get? policy-claims { policy-id: policy-id }))))
    )
    (map-set policy-claims
      { policy-id: policy-id }
      { claim-ids: (unwrap! (as-max-len? (append current-claims claim-id) u10) false) }
    )
  )
)

;; Public Functions

;; Purchase a travel insurance policy
(define-public (purchase-policy 
  (coverage-amount uint)
  (trip-start uint) 
  (trip-end uint)
  (destination (string-ascii 100))
  (policy-type uint))
  (let
    (
      (policy-id (+ (var-get policy-counter) u1))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_INVALID_DATES))
      (trip-duration-days (/ (- trip-end trip-start) u86400))
      (premium (calculate-premium coverage-amount trip-duration-days policy-type))
    )
    ;; Validate inputs
    (asserts! (and (>= policy-type u1) (<= policy-type u3)) ERR_INVALID_POLICY)
    (asserts! (and (>= coverage-amount MIN_PREMIUM) (<= coverage-amount MAX_COVERAGE)) ERR_INVALID_AMOUNT)
    (asserts! (>= premium MIN_PREMIUM) ERR_INVALID_AMOUNT)
    (asserts! (validate-trip-dates trip-start trip-end) ERR_INVALID_DATES)
    
    ;; Transfer premium from user to contract
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    ;; Create policy
    (map-set policies
      { policy-id: policy-id }
      {
        policyholder: tx-sender,
        premium: premium,
        coverage-amount: coverage-amount,
        trip-start: trip-start,
        trip-end: trip-end,
        destination: destination,
        status: STATUS_ACTIVE,
        created-at: current-time,
        policy-type: policy-type
      }
    )
    
    ;; Update counters and balances
    (var-set policy-counter policy-id)
    (var-set total-premiums (+ (var-get total-premiums) premium))
    (var-set contract-balance (+ (var-get contract-balance) premium))
    
    ;; Add policy to user's list
    (try! (add-policy-to-user tx-sender policy-id))
    
    (ok policy-id)
  )
)

;; Submit an insurance claim
(define-public (submit-claim
  (policy-id uint)
  (claim-type uint)
  (amount uint)
  (description (string-ascii 500))
  (evidence-hash (string-ascii 64)))
  (let
    (
      (claim-id (+ (var-get claim-counter) u1))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_INVALID_CLAIM))
      (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR_INVALID_POLICY))
      (max-amount (unwrap! (get-max-claim-amount policy-id claim-type) ERR_INVALID_CLAIM))
    )
    ;; Validate claim
    (asserts! (is-eq tx-sender (get policyholder policy-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status policy-data) STATUS_ACTIVE) ERR_POLICY_NOT_ACTIVE)
    (asserts! (and (>= claim-type u1) (<= claim-type u5)) ERR_INVALID_CLAIM)
    (asserts! (and (> amount u0) (<= amount max-amount)) ERR_INVALID_AMOUNT)
    (asserts! (<= current-time (+ (get trip-end policy-data) CLAIM_WINDOW)) ERR_CLAIM_EXPIRED)
    
    ;; Create claim
    (map-set claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        claimant: tx-sender,
        claim-type: claim-type,
        amount: amount,
        description: description,
        evidence-hash: evidence-hash,
        status: CLAIM_PENDING,
        created-at: current-time,
        processed-at: none,
        processor: none
      }
    )
    
    ;; Update counter and add claim to policy
    (var-set claim-counter claim-id)
    (try! (add-claim-to-policy policy-id claim-id))
    
    (ok claim-id)
  )
)

;; Process a claim (approve or reject)
(define-public (process-claim (claim-id uint) (approve bool))
  (let
    (
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_INVALID_CLAIM))
      (claim-data (unwrap! (map-get? claims { claim-id: claim-id }) ERR_INVALID_CLAIM))
      (new-status (if approve CLAIM_APPROVED CLAIM_REJECTED))
    )
    ;; Check authorization
    (asserts! (or 
      (is-eq tx-sender CONTRACT_OWNER)
      (default-to false (get authorized (map-get? authorized-processors { processor: tx-sender }))))
      ERR_UNAUTHORIZED)
    
    ;; Validate claim can be processed
    (asserts! (is-eq (get status claim-data) CLAIM_PENDING) ERR_ALREADY_PROCESSED)
    
    ;; Update claim status
    (map-set claims
      { claim-id: claim-id }
      (merge claim-data {
        status: new-status,
        processed-at: (some current-time),
        processor: (some tx-sender)
      })
    )
    
    (ok approve)
  )
)

;; Pay approved claim
(define-public (pay-claim (claim-id uint))
  (let
    (
      (claim-data (unwrap! (map-get? claims { claim-id: claim-id }) ERR_INVALID_CLAIM))
      (amount (get amount claim-data))
    )
    ;; Validate claim can be paid
    (asserts! (is-eq (get status claim-data) CLAIM_APPROVED) ERR_INVALID_CLAIM)
    (asserts! (>= (var-get contract-balance) amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer funds to claimant
    (try! (as-contract (stx-transfer? amount tx-sender (get claimant claim-data))))
    
    ;; Update claim status and balances
    (map-set claims
      { claim-id: claim-id }
      (merge claim-data { status: CLAIM_PAID })
    )
    
    (var-set contract-balance (- (var-get contract-balance) amount))
    (var-set total-claims-paid (+ (var-get total-claims-paid) amount))
    
    (ok amount)
  )
)

;; Automatic payout for pre-approved claim types (flight delays with verifiable data)
(define-public (automatic-payout (claim-id uint))
  (let
    (
      (claim-data (unwrap! (map-get? claims { claim-id: claim-id }) ERR_INVALID_CLAIM))
      (amount (get amount claim-data))
    )
    ;; Only allow automatic payout for flight delays
    (asserts! (is-eq (get claim-type claim-data) CLAIM_FLIGHT_DELAY) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status claim-data) CLAIM_PENDING) ERR_ALREADY_PROCESSED)
    (asserts! (>= (var-get contract-balance) amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Auto-approve and pay
    (map-set claims
      { claim-id: claim-id }
      (merge claim-data {
        status: CLAIM_PAID,
        processed-at: (some (unwrap! (get-block-info? time (- block-height u1)) ERR_INVALID_CLAIM)),
        processor: (some (as-contract tx-sender))
      })
    )
    
    ;; Transfer funds
    (try! (as-contract (stx-transfer? amount tx-sender (get claimant claim-data))))
    
    ;; Update balances
    (var-set contract-balance (- (var-get contract-balance) amount))
    (var-set total-claims-paid (+ (var-get total-claims-paid) amount))
    
    (ok amount)
  )
)

;; Cancel policy (before trip starts, partial refund)
(define-public (cancel-policy (policy-id uint))
  (let
    (
      (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR_INVALID_POLICY))
      (current-time (unwrap! (get-block-info? time (- block-height u1)) ERR_INVALID_POLICY))
      (refund-amount (/ (get premium policy-data) u2)) ;; 50% refund
    )
    ;; Validate cancellation
    (asserts! (is-eq tx-sender (get policyholder policy-data)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status policy-data) STATUS_ACTIVE) ERR_POLICY_NOT_ACTIVE)
    (asserts! (> (get trip-start policy-data) current-time) ERR_POLICY_EXPIRED)
    
    ;; Update policy status
    (map-set policies
      { policy-id: policy-id }
      (merge policy-data { status: STATUS_CANCELLED })
    )
    
    ;; Process refund
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get policyholder policy-data))))
    (var-set contract-balance (- (var-get contract-balance) refund-amount))
    
    (ok refund-amount)
  )
)

;; Admin function to add funds to contract
(define-public (add-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) amount))
    (ok amount)
  )
)

;; Admin function to authorize claim processors
(define-public (authorize-processor (processor principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-processors { processor: processor } { authorized: true })
    (ok true)
  )
)

;; Admin function to revoke processor authorization
(define-public (revoke-processor (processor principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-processors { processor: processor } { authorized: false })
    (ok true)
  )
)

;; Read-only functions

;; Get policy details
(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

;; Get claim details
(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

;; Get user's policies
(define-read-only (get-user-policies (user principal))
  (map-get? user-policies { user: user })
)

;; Get policy's claims
(define-read-only (get-policy-claims (policy-id uint))
  (map-get? policy-claims { policy-id: policy-id })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-policies: (var-get policy-counter),
    total-claims: (var-get claim-counter),
    total-premiums: (var-get total-premiums),
    total-claims-paid: (var-get total-claims-paid),
    contract-balance: (var-get contract-balance)
  }
)

;; Get coverage details for policy type
(define-read-only (get-coverage-multipliers (policy-type uint))
  (map-get? coverage-multipliers { policy-type: policy-type })
)

;; Calculate premium for given parameters
(define-read-only (quote-premium (coverage-amount uint) (trip-start uint) (trip-end uint) (policy-type uint))
  (let
    (
      (duration-days (/ (- trip-end trip-start) u86400))
    )
    (if (and 
          (validate-trip-dates trip-start trip-end)
          (and (>= policy-type u1) (<= policy-type u3))
          (and (>= coverage-amount MIN_PREMIUM) (<= coverage-amount MAX_COVERAGE)))
      (ok (calculate-premium coverage-amount duration-days policy-type))
      ERR_INVALID_POLICY
    )
  )
)

;; Check if processor is authorized
(define-read-only (is-authorized-processor (processor principal))
  (default-to false (get authorized (map-get? authorized-processors { processor: processor })))
)