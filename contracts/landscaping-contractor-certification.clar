;; Landscaping Contractor Certification Contract
;; Manages licenses for lawn care and landscaping businesses

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-INPUT (err u201))
(define-constant ERR-CONTRACTOR-NOT-FOUND (err u202))
(define-constant ERR-LICENSE-EXPIRED (err u203))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u204))
(define-constant ERR-ALREADY-CERTIFIED (err u205))
(define-constant ERR-CERTIFICATION-NOT-FOUND (err u206))

;; Data Variables
(define-data-var certification-counter uint u0)
(define-data-var job-counter uint u0)
(define-data-var certification-fee uint u3000000) ;; 3 STX in microSTX
(define-data-var renewal-fee uint u2000000) ;; 2 STX in microSTX

;; Data Maps
(define-map landscaping-contractors
  { contractor-id: uint }
  {
    owner: principal,
    business-name: (string-ascii 100),
    license-type: (string-ascii 50),
    specializations: (list 5 (string-ascii 50)),
    certification-date: uint,
    expiry-date: uint,
    is-active: bool,
    completed-jobs: uint,
    customer-rating: uint,
    insurance-verified: bool
  }
)

(define-map landscaping-jobs
  { job-id: uint }
  {
    contractor-id: uint,
    client: principal,
    service-type: (string-ascii 100),
    property-address: (string-ascii 200),
    job-description: (string-ascii 500),
    estimated-hours: uint,
    hourly-rate: uint,
    start-date: uint,
    completion-date: (optional uint),
    status: (string-ascii 20),
    client-rating: (optional uint)
  }
)

(define-map contractor-by-owner
  { owner: principal }
  { contractor-id: uint }
)

(define-map performance-metrics
  { contractor-id: uint }
  {
    total-revenue: uint,
    average-rating: uint,
    on-time-completion: uint,
    safety-violations: uint,
    customer-complaints: uint
  }
)

;; Public Functions

;; Register and certify a landscaping contractor
(define-public (certify-contractor
  (business-name (string-ascii 100))
  (license-type (string-ascii 50))
  (specializations (list 5 (string-ascii 50)))
  (insurance-verified bool))
  (let
    (
      (new-contractor-id (+ (var-get certification-counter) u1))
      (expiry-date (+ block-height u52560)) ;; ~1 year in blocks
    )
    (asserts! (> (len business-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len license-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len specializations) u0) ERR-INVALID-INPUT)
    (asserts! (>= (stx-get-balance tx-sender) (var-get certification-fee)) ERR-INSUFFICIENT-PAYMENT)

    (try! (stx-transfer? (var-get certification-fee) tx-sender CONTRACT-OWNER))

    (map-set landscaping-contractors
      { contractor-id: new-contractor-id }
      {
        owner: tx-sender,
        business-name: business-name,
        license-type: license-type,
        specializations: specializations,
        certification-date: block-height,
        expiry-date: expiry-date,
        is-active: true,
        completed-jobs: u0,
        customer-rating: u5,
        insurance-verified: insurance-verified
      }
    )

    (map-set contractor-by-owner
      { owner: tx-sender }
      { contractor-id: new-contractor-id }
    )

    (map-set performance-metrics
      { contractor-id: new-contractor-id }
      {
        total-revenue: u0,
        average-rating: u5,
        on-time-completion: u100,
        safety-violations: u0,
        customer-complaints: u0
      }
    )

    (var-set certification-counter new-contractor-id)
    (ok new-contractor-id)
  )
)

;; Create a new landscaping job
(define-public (create-job
  (contractor-id uint)
  (client principal)
  (service-type (string-ascii 100))
  (property-address (string-ascii 200))
  (job-description (string-ascii 500))
  (estimated-hours uint)
  (hourly-rate uint))
  (let
    (
      (new-job-id (+ (var-get job-counter) u1))
      (contractor (unwrap! (map-get? landscaping-contractors { contractor-id: contractor-id }) ERR-CONTRACTOR-NOT-FOUND))
    )
    (asserts! (is-eq (get owner contractor) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active contractor) ERR-NOT-AUTHORIZED)
    (asserts! (< block-height (get expiry-date contractor)) ERR-LICENSE-EXPIRED)
    (asserts! (> (len service-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len property-address) u0) ERR-INVALID-INPUT)
    (asserts! (> estimated-hours u0) ERR-INVALID-INPUT)
    (asserts! (> hourly-rate u0) ERR-INVALID-INPUT)

    (map-set landscaping-jobs
      { job-id: new-job-id }
      {
        contractor-id: contractor-id,
        client: client,
        service-type: service-type,
        property-address: property-address,
        job-description: job-description,
        estimated-hours: estimated-hours,
        hourly-rate: hourly-rate,
        start-date: block-height,
        completion-date: none,
        status: "active",
        client-rating: none
      }
    )

    (var-set job-counter new-job-id)
    (ok new-job-id)
  )
)

;; Complete a landscaping job
(define-public (complete-job (job-id uint))
  (let
    (
      (job (unwrap! (map-get? landscaping-jobs { job-id: job-id }) ERR-INVALID-INPUT))
      (contractor (unwrap! (map-get? landscaping-contractors { contractor-id: (get contractor-id job) }) ERR-CONTRACTOR-NOT-FOUND))
      (metrics (unwrap! (map-get? performance-metrics { contractor-id: (get contractor-id job) }) ERR-CONTRACTOR-NOT-FOUND))
      (total-cost (* (get estimated-hours job) (get hourly-rate job)))
    )
    (asserts! (is-eq (get owner contractor) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status job) "active") ERR-INVALID-INPUT)

    (map-set landscaping-jobs
      { job-id: job-id }
      (merge job {
        status: "completed",
        completion-date: (some block-height)
      })
    )

    ;; Update contractor stats
    (map-set landscaping-contractors
      { contractor-id: (get contractor-id job) }
      (merge contractor { completed-jobs: (+ (get completed-jobs contractor) u1) })
    )

    ;; Update performance metrics
    (map-set performance-metrics
      { contractor-id: (get contractor-id job) }
      (merge metrics { total-revenue: (+ (get total-revenue metrics) total-cost) })
    )

    (ok true)
  )
)

;; Rate a completed job (client only)
(define-public (rate-job (job-id uint) (rating uint))
  (let
    (
      (job (unwrap! (map-get? landscaping-jobs { job-id: job-id }) ERR-INVALID-INPUT))
    )
    (asserts! (is-eq (get client job) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status job) "completed") ERR-INVALID-INPUT)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-INPUT)

    (map-set landscaping-jobs
      { job-id: job-id }
      (merge job { client-rating: (some rating) })
    )
    (ok true)
  )
)

;; Renew contractor certification
(define-public (renew-certification (contractor-id uint))
  (let
    (
      (contractor (unwrap! (map-get? landscaping-contractors { contractor-id: contractor-id }) ERR-CONTRACTOR-NOT-FOUND))
      (new-expiry (+ block-height u52560)) ;; ~1 year in blocks
    )
    (asserts! (is-eq (get owner contractor) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= (stx-get-balance tx-sender) (var-get renewal-fee)) ERR-INSUFFICIENT-PAYMENT)

    (try! (stx-transfer? (var-get renewal-fee) tx-sender CONTRACT-OWNER))

    (map-set landscaping-contractors
      { contractor-id: contractor-id }
      (merge contractor { expiry-date: new-expiry })
    )
    (ok true)
  )
)

;; Suspend contractor (contract owner only)
(define-public (suspend-contractor (contractor-id uint) (reason (string-ascii 200)))
  (let
    (
      (contractor (unwrap! (map-get? landscaping-contractors { contractor-id: contractor-id }) ERR-CONTRACTOR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len reason) u0) ERR-INVALID-INPUT)

    (map-set landscaping-contractors
      { contractor-id: contractor-id }
      (merge contractor { is-active: false })
    )
    (ok true)
  )
)

;; Record safety violation
(define-public (record-safety-violation (contractor-id uint))
  (let
    (
      (metrics (unwrap! (map-get? performance-metrics { contractor-id: contractor-id }) ERR-CONTRACTOR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set performance-metrics
      { contractor-id: contractor-id }
      (merge metrics { safety-violations: (+ (get safety-violations metrics) u1) })
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-contractor (contractor-id uint))
  (map-get? landscaping-contractors { contractor-id: contractor-id })
)

(define-read-only (get-job (job-id uint))
  (map-get? landscaping-jobs { job-id: job-id })
)

(define-read-only (get-contractor-by-owner (owner principal))
  (map-get? contractor-by-owner { owner: owner })
)

(define-read-only (get-performance-metrics (contractor-id uint))
  (map-get? performance-metrics { contractor-id: contractor-id })
)

(define-read-only (get-certification-fee)
  (var-get certification-fee)
)

(define-read-only (get-renewal-fee)
  (var-get renewal-fee)
)

(define-read-only (get-certification-counter)
  (var-get certification-counter)
)

(define-read-only (get-job-counter)
  (var-get job-counter)
)
