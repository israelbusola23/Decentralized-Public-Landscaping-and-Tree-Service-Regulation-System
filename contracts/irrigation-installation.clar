;; Irrigation System Installation Contract
;; Manages permits for sprinkler system installation and water usage

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-INPUT (err u501))
(define-constant ERR-PERMIT-NOT-FOUND (err u502))
(define-constant ERR-INSTALLER-NOT-CERTIFIED (err u503))
(define-constant ERR-WATER-LIMIT-EXCEEDED (err u504))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u505))
(define-constant ERR-SYSTEM-NOT-FOUND (err u506))

;; Data Variables
(define-data-var permit-counter uint u0)
(define-data-var installer-counter uint u0)
(define-data-var system-counter uint u0)
(define-data-var permit-fee uint u1500000) ;; 1.5 STX in microSTX
(define-data-var certification-fee uint u3000000) ;; 3 STX in microSTX
(define-data-var water-rate-per-gallon uint u100) ;; microSTX per gallon

;; Data Maps
(define-map certified-installers
  { installer-id: uint }
  {
    owner: principal,
    company-name: (string-ascii 100),
    license-number: (string-ascii 50),
    certification-date: uint,
    expiry-date: uint,
    specializations: (list 5 (string-ascii 50)),
    is-active: bool,
    installations-completed: uint,
    efficiency-rating: uint
  }
)

(define-map irrigation-permits
  { permit-id: uint }
  {
    installer-id: uint,
    property-owner: principal,
    property-address: (string-ascii 200),
    system-type: (string-ascii 100),
    coverage-area: uint,
    estimated-water-usage: uint,
    installation-date: uint,
    permit-expiry: uint,
    status: (string-ascii 20),
    environmental-impact-assessed: bool
  }
)

(define-map irrigation-systems
  { system-id: uint }
  {
    permit-id: uint,
    installer-id: uint,
    property-owner: principal,
    system-components: (list 10 (string-ascii 100)),
    installation-date: uint,
    water-source: (string-ascii 100),
    flow-rate: uint,
    efficiency-rating: uint,
    smart-controls: bool,
    maintenance-schedule: uint
  }
)

(define-map water-usage-tracking
  { system-id: uint, month: uint }
  {
    gallons-used: uint,
    efficiency-score: uint,
    conservation-measures: (list 5 (string-ascii 100)),
    cost-this-month: uint,
    violations: uint
  }
)

(define-map installer-by-owner
  { owner: principal }
  { installer-id: uint }
)

(define-map water-conservation-zones
  { zone-id: (string-ascii 50) }
  {
    zone-name: (string-ascii 100),
    water-restriction-level: uint,
    max-daily-usage: uint,
    restricted-hours: (list 5 uint),
    drought-status: bool
  }
)

;; Public Functions

;; Certify irrigation installer
(define-public (certify-installer
  (company-name (string-ascii 100))
  (license-number (string-ascii 50))
  (specializations (list 5 (string-ascii 50))))
  (let
    (
      (new-installer-id (+ (var-get installer-counter) u1))
      (expiry-date (+ block-height u52560)) ;; ~1 year in blocks
    )
    (asserts! (> (len company-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len license-number) u0) ERR-INVALID-INPUT)
    (asserts! (> (len specializations) u0) ERR-INVALID-INPUT)
    (asserts! (>= (stx-get-balance tx-sender) (var-get certification-fee)) ERR-INSUFFICIENT-PAYMENT)

    (try! (stx-transfer? (var-get certification-fee) tx-sender CONTRACT-OWNER))

    (map-set certified-installers
      { installer-id: new-installer-id }
      {
        owner: tx-sender,
        company-name: company-name,
        license-number: license-number,
        certification-date: block-height,
        expiry-date: expiry-date,
        specializations: specializations,
        is-active: true,
        installations-completed: u0,
        efficiency-rating: u5
      }
    )

    (map-set installer-by-owner
      { owner: tx-sender }
      { installer-id: new-installer-id }
    )

    (var-set installer-counter new-installer-id)
    (ok new-installer-id)
  )
)

;; Apply for irrigation installation permit
(define-public (apply-for-installation-permit
  (installer-id uint)
  (property-owner principal)
  (property-address (string-ascii 200))
  (system-type (string-ascii 100))
  (coverage-area uint)
  (estimated-water-usage uint))
  (let
    (
      (new-permit-id (+ (var-get permit-counter) u1))
      (installer (unwrap! (map-get? certified-installers { installer-id: installer-id }) ERR-INSTALLER-NOT-CERTIFIED))
      (permit-expiry (+ block-height u4320)) ;; ~30 days in blocks
    )
    (asserts! (is-eq (get owner installer) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active installer) ERR-INSTALLER-NOT-CERTIFIED)
    (asserts! (< block-height (get expiry-date installer)) ERR-INSTALLER-NOT-CERTIFIED)
    (asserts! (> (len property-address) u0) ERR-INVALID-INPUT)
    (asserts! (> (len system-type) u0) ERR-INVALID-INPUT)
    (asserts! (> coverage-area u0) ERR-INVALID-INPUT)
    (asserts! (> estimated-water-usage u0) ERR-INVALID-INPUT)
    (asserts! (<= estimated-water-usage u50000) ERR-WATER-LIMIT-EXCEEDED) ;; Max 50,000 gallons/month
    (asserts! (>= (stx-get-balance tx-sender) (var-get permit-fee)) ERR-INSUFFICIENT-PAYMENT)

    (try! (stx-transfer? (var-get permit-fee) tx-sender CONTRACT-OWNER))

    (map-set irrigation-permits
      { permit-id: new-permit-id }
      {
        installer-id: installer-id,
        property-owner: property-owner,
        property-address: property-address,
        system-type: system-type,
        coverage-area: coverage-area,
        estimated-water-usage: estimated-water-usage,
        installation-date: block-height,
        permit-expiry: permit-expiry,
        status: "pending",
        environmental-impact-assessed: false
      }
    )

    (var-set permit-counter new-permit-id)
    (ok new-permit-id)
  )
)

;; Approve installation permit (contract owner only)
(define-public (approve-installation-permit (permit-id uint))
  (let
    (
      (permit (unwrap! (map-get? irrigation-permits { permit-id: permit-id }) ERR-PERMIT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status permit) "pending") ERR-INVALID-INPUT)

    (map-set irrigation-permits
      { permit-id: permit-id }
      (merge permit {
        status: "approved",
        environmental-impact-assessed: true
      })
    )
    (ok true)
  )
)

;; Install irrigation system
(define-public (install-system
  (permit-id uint)
  (system-components (list 10 (string-ascii 100)))
  (water-source (string-ascii 100))
  (flow-rate uint)
  (efficiency-rating uint)
  (smart-controls bool))
  (let
    (
      (new-system-id (+ (var-get system-counter) u1))
      (permit (unwrap! (map-get? irrigation-permits { permit-id: permit-id }) ERR-PERMIT-NOT-FOUND))
      (installer (unwrap! (map-get? certified-installers { installer-id: (get installer-id permit) }) ERR-INSTALLER-NOT-CERTIFIED))
      (maintenance-schedule (+ block-height u2160)) ;; ~15 days
    )
    (asserts! (is-eq (get owner installer) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status permit) "approved") ERR-INVALID-INPUT)
    (asserts! (< block-height (get permit-expiry permit)) ERR-PERMIT-NOT-FOUND)
    (asserts! (> (len system-components) u0) ERR-INVALID-INPUT)
    (asserts! (> (len water-source) u0) ERR-INVALID-INPUT)
    (asserts! (> flow-rate u0) ERR-INVALID-INPUT)
    (asserts! (and (>= efficiency-rating u1) (<= efficiency-rating u10)) ERR-INVALID-INPUT)

    (map-set irrigation-systems
      { system-id: new-system-id }
      {
        permit-id: permit-id,
        installer-id: (get installer-id permit),
        property-owner: (get property-owner permit),
        system-components: system-components,
        installation-date: block-height,
        water-source: water-source,
        flow-rate: flow-rate,
        efficiency-rating: efficiency-rating,
        smart-controls: smart-controls,
        maintenance-schedule: maintenance-schedule
      }
    )

    ;; Update installer stats
    (map-set certified-installers
      { installer-id: (get installer-id permit) }
      (merge installer { installations-completed: (+ (get installations-completed installer) u1) })
    )

    ;; Update permit status
    (map-set irrigation-permits
      { permit-id: permit-id }
      (merge permit { status: "installed" })
    )

    (var-set system-counter new-system-id)
    (ok new-system-id)
  )
)

;; Record monthly water usage
(define-public (record-water-usage
  (system-id uint)
  (month uint)
  (gallons-used uint)
  (conservation-measures (list 5 (string-ascii 100))))
  (let
    (
      (system (unwrap! (map-get? irrigation-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
      (cost-this-month (* gallons-used (var-get water-rate-per-gallon)))
      (efficiency-score (if (> gallons-used u10000) u3
                        (if (> gallons-used u5000) u7 u10)))
    )
    (asserts! (is-eq (get property-owner system) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> gallons-used u0) ERR-INVALID-INPUT)

    (map-set water-usage-tracking
      { system-id: system-id, month: month }
      {
        gallons-used: gallons-used,
        efficiency-score: efficiency-score,
        conservation-measures: conservation-measures,
        cost-this-month: cost-this-month,
        violations: u0
      }
    )
    (ok true)
  )
)

;; Set water conservation zone
(define-public (set-conservation-zone
  (zone-id (string-ascii 50))
  (zone-name (string-ascii 100))
  (water-restriction-level uint)
  (max-daily-usage uint)
  (restricted-hours (list 5 uint))
  (drought-status bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len zone-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len zone-name) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= water-restriction-level u1) (<= water-restriction-level u5)) ERR-INVALID-INPUT)
    (asserts! (> max-daily-usage u0) ERR-INVALID-INPUT)

    (map-set water-conservation-zones
      { zone-id: zone-id }
      {
        zone-name: zone-name,
        water-restriction-level: water-restriction-level,
        max-daily-usage: max-daily-usage,
        restricted-hours: restricted-hours,
        drought-status: drought-status
      }
    )
    (ok true)
  )
)

;; Record water usage violation
(define-public (record-usage-violation (system-id uint) (month uint))
  (let
    (
      (usage-record (unwrap! (map-get? water-usage-tracking { system-id: system-id, month: month }) ERR-INVALID-INPUT))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set water-usage-tracking
      { system-id: system-id, month: month }
      (merge usage-record { violations: (+ (get violations usage-record) u1) })
    )
    (ok true)
  )
)

;; Update system efficiency rating
(define-public (update-system-efficiency (system-id uint) (new-rating uint))
  (let
    (
      (system (unwrap! (map-get? irrigation-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-rating u1) (<= new-rating u10)) ERR-INVALID-INPUT)

    (map-set irrigation-systems
      { system-id: system-id }
      (merge system { efficiency-rating: new-rating })
    )
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-installer (installer-id uint))
  (map-get? certified-installers { installer-id: installer-id })
)

(define-read-only (get-permit (permit-id uint))
  (map-get? irrigation-permits { permit-id: permit-id })
)

(define-read-only (get-system (system-id uint))
  (map-get? irrigation-systems { system-id: system-id })
)

(define-read-only (get-water-usage (system-id uint) (month uint))
  (map-get? water-usage-tracking { system-id: system-id, month: month })
)

(define-read-only (get-installer-by-owner (owner principal))
  (map-get? installer-by-owner { owner: owner })
)

(define-read-only (get-conservation-zone (zone-id (string-ascii 50)))
  (map-get? water-conservation-zones { zone-id: zone-id })
)

(define-read-only (get-permit-fee)
  (var-get permit-fee)
)

(define-read-only (get-certification-fee)
  (var-get certification-fee)
)

(define-read-only (get-water-rate)
  (var-get water-rate-per-gallon)
)

(define-read-only (get-system-counter)
  (var-get system-counter)
)
