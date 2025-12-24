  // Usamos la API v2 de Cloud Functions para Firestore
  const { onDocumentCreated } = require("firebase-functions/v2/firestore");
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, FieldValue } = require("firebase-admin/firestore");
  const { onCall, HttpsError } = require("firebase-functions/v2/https");
  const PLATFORM_FEE_BPS = 2000; // 20%
  const { AccessToken } = require("livekit-server-sdk");



  // Inicializar Firebase Admin
  initializeApp();
  const db = getFirestore();

  // 🔥 Se ejecuta cuando se crea una foto o video en la galería
  exports.onGalleryItemCreated = onDocumentCreated(
    "users/{uid}/gallery/{mediaId}",
    async (event) => {
      const snap = event.data;
      if (!snap) {
        console.log("No hay snapshot en el evento, se ignora.");
        return;
      }

      const data = snap.data();
      const params = event.params || {};
      const uid = params.uid;
      const mediaId = params.mediaId;

      console.log("Nuevo media en galería:", uid, mediaId, data);

      try {
        await snap.ref.update({
          status: "approved", // 👈 por ahora aprobamos todo
          moderatedAt: FieldValue.serverTimestamp(),
        });

        console.log("Media aprobado automáticamente:", uid, mediaId);
      } catch (err) {
        console.error("Error al actualizar el media:", err);
      }
    }
  );
  // ============================
  // PAYMENTS (STRIPE REAL): SetupIntent para guardar tarjeta del hablante
  // ============================
  const { defineSecret } = require("firebase-functions/params");
  const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
  const STRIPE_PUBLISHABLE_KEY = defineSecret("STRIPE_PUBLISHABLE_KEY");

  // API version para ephemeral keys (usa una fija y estable)
  const EPHEMERAL_KEY_API_VERSION = "2023-10-16";

  exports.payments_prepareSetupIntent = onCall(
    {
      region: "us-central1",
      secrets: [STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY],
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Auth requerida.");
      }

      const uid = request.auth.uid;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data() || {};

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      // 1) Crear/obtener Customer
      let customerId = (user.stripeCustomerId || "").trim();
      if (!customerId) {
        const customer = await stripe.customers.create({
          metadata: { firebaseUid: uid },
        });
        customerId = customer.id;

        await userRef.set(
          {
            stripeCustomerId: customerId,
            stripeUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      // 2) Ephemeral Key (necesaria para PaymentSheet en mobile)
      const ephemeralKey = await stripe.ephemeralKeys.create(
        { customer: customerId },
        { apiVersion: EPHEMERAL_KEY_API_VERSION }
      );

      // 3) SetupIntent (guardar método de pago para cobros futuros)
      const setupIntent = await stripe.setupIntents.create({
        customer: customerId,
        usage: "off_session",
        payment_method_types: ["card"],
      });

      return {
        customerId,
        ephemeralKeySecret: ephemeralKey.secret,
        setupIntentClientSecret: setupIntent.client_secret,
        publishableKey: STRIPE_PUBLISHABLE_KEY.value(),
      };
    }
  );
  exports.payments_finalizeSetupIntent = onCall(
    {
      region: "us-central1",
      secrets: [STRIPE_SECRET_KEY],
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Auth requerida.");
      }

      const uid = request.auth.uid;
      const setupIntentClientSecret = (request.data?.setupIntentClientSecret || "").trim();
      if (!setupIntentClientSecret) {
        throw new HttpsError("invalid-argument", "setupIntentClientSecret requerido.");
      }

      // Extraer el setupIntentId del client secret: "seti_123_secret_abc" -> "seti_123"
      const setupIntentId = setupIntentClientSecret.split("_secret_")[0];

      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data() || {};
      const customerId = (user.stripeCustomerId || "").trim();
      if (!customerId) {
        throw new HttpsError("failed-precondition", "stripeCustomerId no existe en el usuario.");
      }

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      // 1) Obtener el SetupIntent ya confirmado
      const si = await stripe.setupIntents.retrieve(setupIntentId);
      const paymentMethodId = typeof si.payment_method === "string" ? si.payment_method : si.payment_method?.id;

      if (!paymentMethodId) {
        throw new HttpsError("failed-precondition", "El SetupIntent no tiene payment_method.");
      }

      // 2) Asegurar que el PM está ligado al customer (normalmente ya lo está)
      // y ponerlo como default para invoice/charges.
      await stripe.customers.update(customerId, {
        invoice_settings: { default_payment_method: paymentMethodId },
      });

      // 3) Leer detalles del payment method para brand/last4
      const pm = await stripe.paymentMethods.retrieve(paymentMethodId);
      const brand = pm?.card?.brand || null;
      const last4 = pm?.card?.last4 || null;

      // 4) Guardar en Firestore para tu UI
      await userRef.set(
        {
          stripeDefaultPaymentMethodId: paymentMethodId,
          stripeDefaultPmBrand: brand,
          stripeDefaultPmLast4: last4,
          stripeUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return { ok: true, paymentMethodId, brand, last4 };
    }
  );

  exports.payments_detachDefaultPaymentMethod = onCall(
    {
      region: "us-central1",
      secrets: [STRIPE_SECRET_KEY],
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Auth requerida.");
      }

      const uid = request.auth.uid;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data() || {};

      const customerId = (user.stripeCustomerId || "").trim();
      if (!customerId) {
        throw new HttpsError("failed-precondition", "stripeCustomerId no existe.");
      }

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      // Si guardamos el PM id en Firestore, lo usamos directo
      let pmId = (user.stripeDefaultPaymentMethodId || "").trim();

      // Si no está guardado (por compat), lo pedimos a Stripe
      if (!pmId) {
        const customer = await stripe.customers.retrieve(customerId);
        const defaultPm = customer?.invoice_settings?.default_payment_method;
        pmId = typeof defaultPm === "string" ? defaultPm : defaultPm?.id;
      }

      if (!pmId) {
        // No hay nada que quitar: limpiamos Firestore y listo
        await userRef.set(
          {
            stripeDefaultPaymentMethodId: FieldValue.delete(),
            stripeDefaultPmBrand: FieldValue.delete(),
            stripeDefaultPmLast4: FieldValue.delete(),
            stripeUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return { ok: true, alreadyEmpty: true };
      }

      // 1) Quitar default del customer
      await stripe.customers.update(customerId, {
        invoice_settings: { default_payment_method: null },
      });

      // 2) Detach del customer (opcional pero recomendado para "borrar")
      await stripe.paymentMethods.detach(pmId);

      // 3) Limpiar Firestore
      await userRef.set(
        {
          stripeDefaultPaymentMethodId: FieldValue.delete(),
          stripeDefaultPmBrand: FieldValue.delete(),
          stripeDefaultPmLast4: FieldValue.delete(),
          stripeUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return { ok: true, detached: true, paymentMethodId: pmId };
    }
  );

  exports.payments_authorizeSessionHold = onCall(
    { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Auth requerida.");
      }

      const uid = request.auth.uid;
      const sessionId = (request.data?.sessionId || "").toString().trim();
      if (!sessionId) throw new HttpsError("invalid-argument", "Falta sessionId.");

      const sessionRef = db.collection("sessions").doc(sessionId);
      const sessionSnap = await sessionRef.get();
      if (!sessionSnap.exists) throw new HttpsError("not-found", "Sesión no existe.");

      const session = sessionSnap.data() || {};

      // ✅ Solo el hablante puede autorizar el hold
      const speakerId = (session.speakerId || "").toString();
      if (speakerId !== uid) {
        throw new HttpsError("permission-denied", "Solo el hablante puede autorizar el hold.");
      }

      // ✅ Si ya existe, no recrear
      const existingPi = (session.paymentIntentId || "").toString().trim();
      if (existingPi) return { ok: true, already: true, paymentIntentId: existingPi };

      // ✅ Monto fijo de la sesión
      const amountCents = Number(session.priceCents || 0);
      if (!amountCents || amountCents <= 0) {
        throw new HttpsError("failed-precondition", "La sesión no tiene priceCents válido.");
      }

      // ✅ Método del hablante
      const userSnap = await db.collection("users").doc(uid).get();
      const user = userSnap.data() || {};
      const customerId = (user.stripeCustomerId || "").toString().trim();
      const pmId = (user.stripeDefaultPaymentMethodId || "").toString().trim();

      if (!customerId || !pmId) {
        throw new HttpsError("failed-precondition", "El hablante no tiene método de pago listo.");
      }

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      try {
        const pi = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: "mxn",
          customer: customerId,
          payment_method: pmId,
          confirm: true,
          off_session: true,
          capture_method: "manual", // ✅ HOLD
          description: `Lissen hold - session ${sessionId}`,
          metadata: { sessionId, speakerId: uid },
        });

        await sessionRef.set(
          {
            paymentIntentId: pi.id,
            paymentIntentStatus: pi.status,
            holdAmountCents: amountCents,
            holdCurrency: "mxn",
            holdAuthorizedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return { ok: true, paymentIntentId: pi.id, status: pi.status };
      } catch (err) {
        const msg =
          (err && err.raw && err.raw.message) ? err.raw.message : (err?.message || String(err));
        throw new HttpsError("failed-precondition", `Hold falló: ${msg}`);
      }
    }
  );

  // ============================================================
  // PAYMENTS (STRIPE REAL): HOLD al aceptar una oferta (SIN crear sesión si falla)
  // ============================================================
  exports.payments_authorizeOfferHold = onCall(
    { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Auth requerida.");
      }

      const uid = request.auth.uid;
      const offerId = (request.data?.offerId || "").toString().trim();
      const sessionId = (request.data?.sessionId || "").toString().trim();

      if (!offerId) throw new HttpsError("invalid-argument", "Falta offerId.");
      if (!sessionId) throw new HttpsError("invalid-argument", "Falta sessionId.");

      const offerRef = db.collection("offers").doc(offerId);
      const offerSnap = await offerRef.get();
      if (!offerSnap.exists) throw new HttpsError("not-found", "Oferta no existe.");

      const offer = offerSnap.data() || {};

      // ✅ Solo el hablante puede autorizar el hold
      const speakerId = (offer.speakerId || "").toString();
      if (speakerId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Solo el hablante puede autorizar el hold."
        );
      }

      // ✅ Debe estar pendiente (si ya está usada, regresamos info)
      const status = (offer.status || "active").toString();
      const existingSession = (offer.lastSessionId || "").toString().trim();
      if (status === "used" && existingSession) {
        return { ok: true, alreadyUsed: true, sessionId: existingSession };
      }

      if (status !== "pending_speaker") {
        throw new HttpsError(
          "failed-precondition",
          "La oferta no está en estado pending_speaker."
        );
      }

      const pendingCompanionId = (offer.pendingCompanionId || "").toString().trim();
      if (!pendingCompanionId) {
        throw new HttpsError(
          "failed-precondition",
          "La oferta no tiene pendingCompanionId."
        );
      }

      // ✅ Si ya hay un hold creado para esta oferta, no recrear
      const existingPi = (offer.holdPaymentIntentId || "").toString().trim();
      if (existingPi) {
        return {
          ok: true,
          already: true,
          paymentIntentId: existingPi,
          reservedSessionId: (offer.reservedSessionId || "").toString().trim() || sessionId,
        };
      }

      // ✅ Monto fijo de la oferta
      const asNumber = (v) => {
        const n = Number(v);
        return Number.isFinite(n) ? n : 0;
      };

      let amountCents = asNumber(offer.priceCents || offer.totalMinAmountCents || 0);

      if (!amountCents || amountCents <= 0) {
        const durationMinutes = asNumber(offer.durationMinutes || offer.minMinutes || 0);
        const pricePerMinuteCents = asNumber(offer.pricePerMinuteCents || 0);
        if (durationMinutes > 0 && pricePerMinuteCents > 0) {
          amountCents = durationMinutes * pricePerMinuteCents;
        }
      }

      if (!amountCents || amountCents <= 0) {
        throw new HttpsError(
          "failed-precondition",
          "La oferta no tiene un monto válido (priceCents/totalMinAmountCents)."
        );
      }

      // Currency: por ahora usamos el de la oferta o MXN por defecto.
      const currency = (offer.currency || "mxn").toString().trim().toLowerCase() || "mxn";

      // ✅ Método del hablante
      const userSnap = await db.collection("users").doc(uid).get();
      const user = userSnap.data() || {};
      const customerId = (user.stripeCustomerId || "").toString().trim();
      const pmId = (user.stripeDefaultPaymentMethodId || "").toString().trim();

      if (!customerId || !pmId) {
        throw new HttpsError(
          "failed-precondition",
          "El hablante no tiene método de pago listo."
        );
      }

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      try {
        const pi = await stripe.paymentIntents.create({
          amount: amountCents,
          currency,
          customer: customerId,
          payment_method: pmId,
          confirm: true,
          off_session: true,
          capture_method: "manual", // ✅ HOLD
          description: `Lissen hold - offer ${offerId}`,
          metadata: {
            offerId,
            reservedSessionId: sessionId,
            speakerId: uid,
            companionId: pendingCompanionId,
          },
        });

        await offerRef.set(
          {
            holdPaymentIntentId: pi.id,
            holdPaymentIntentStatus: pi.status,
            holdAmountCents: amountCents,
            holdCurrency: currency,
            holdAuthorizedAt: FieldValue.serverTimestamp(),
            reservedSessionId: sessionId,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return {
          ok: true,
          paymentIntentId: pi.id,
          status: pi.status,
          reservedSessionId: sessionId,
        };
      } catch (err) {
        const msg =
          err && err.raw && err.raw.message
            ? err.raw.message
            : err?.message || String(err);
        throw new HttpsError("failed-precondition", `Hold falló: ${msg}`);
      }
    }
  );

  // ============================================================
  // PAYMENTS (STRIPE REAL): CAPTURE al finalizar sesión
  // ============================================================
  exports.payments_captureSessionPayment = onCall(
    { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Auth requerida.");
      }

      const uid = request.auth.uid;
      const sessionId = (request.data?.sessionId || "").toString().trim();
      if (!sessionId) throw new HttpsError("invalid-argument", "Falta sessionId.");

      const asInt = (v) => {
        const n = Number(v);
        return Number.isFinite(n) ? Math.trunc(n) : 0;
      };

      const sessionRef = db.collection("sessions").doc(sessionId);
      const snap = await sessionRef.get();
      if (!snap.exists) throw new HttpsError("not-found", "Sesión no existe.");

      const session = snap.data() || {};

      // ✅ Solo participantes (hablante o compañera) pueden disparar capture
      const speakerId = (session.speakerId || "").toString().trim();
      const companionId = (session.companionId || "").toString().trim();
      if (uid !== speakerId && uid !== companionId) {
        throw new HttpsError("permission-denied", "No eres participante de esta sesión.");
      }

      // ✅ Debe estar completada
      const status = (session.status || "").toString().trim();
      if (status !== "completed") {
        throw new HttpsError("failed-precondition", "La sesión aún no está completed.");
      }

      const paymentIntentId = (session.paymentIntentId || "").toString().trim();
      if (!paymentIntentId) {
        throw new HttpsError("failed-precondition", "La sesión no tiene paymentIntentId.");
      }

      const durationMinutes = asInt(session.durationMinutes || 0);
      const holdAmountCents = asInt(session.holdAmountCents || session.priceCents || 0);
      const currency = ((session.holdCurrency || "mxn").toString().trim().toLowerCase()) || "mxn";

      if (!durationMinutes || durationMinutes <= 0) {
        throw new HttpsError("failed-precondition", "La sesión no tiene durationMinutes válido.");
      }
      if (!holdAmountCents || holdAmountCents <= 0) {
        throw new HttpsError("failed-precondition", "La sesión no tiene holdAmountCents/priceCents válido.");
      }

      const endedBy = (session.endedBy || "").toString().trim(); // 'speaker' | 'companion' | 'timeout'
      let billingMinutes = asInt(session.billingMinutes || 0);
      let realMinutes = asInt(session.realDurationMinutes || 0);

      // ✅ Fallback si por alguna razón no existen billingMinutes/realDurationMinutes
      if (billingMinutes <= 0) {
        const createdAt =
          session.createdAt && typeof session.createdAt.toDate === "function"
            ? session.createdAt.toDate()
            : null;

        const completedAt =
          session.completedAt && typeof session.completedAt.toDate === "function"
            ? session.completedAt.toDate()
            : null;

        if (createdAt && completedAt) {
          const ms = Math.max(0, completedAt.getTime() - createdAt.getTime());
          realMinutes = Math.max(0, Math.ceil(ms / 60000));
        }

        if (endedBy === "companion") {
          billingMinutes = Math.max(10, realMinutes);
        } else {
          billingMinutes = durationMinutes; // speaker/timeout => todo
        }
      }

      // Candados
      billingMinutes = Math.max(0, Math.min(durationMinutes, billingMinutes));

      // ✅ Captura basada en billingMinutes
      let amountToCapture = Math.ceil((holdAmountCents * billingMinutes) / durationMinutes);
      amountToCapture = Math.max(1, Math.min(holdAmountCents, amountToCapture));

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      // Helper inline: intenta crear Transfer si falta
      const maybeCreateTransfer = async (paymentIntentObj, capturedAmountCents) => {
        // Ya existe transfer
        if ((session.transferId || "").toString().trim()) {
          return { skipped: true, reason: "already_has_transfer" };
        }

        // Necesitamos companionId y su cuenta Connect
        if (!companionId) {
          return { skipped: true, reason: "missing_companionId" };
        }

        const companionSnap = await db.collection("users").doc(companionId).get();
        const companion = companionSnap.data() || {};
        const destinationAccountId = (companion.stripeConnectAccountId || "").toString().trim();

        if (!destinationAccountId) {
          // No tronamos el capture: solo marcamos que faltó connect
          await sessionRef.set(
            {
              transferStatus: "missing_connect_account",
              transferUpdatedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          return { skipped: true, reason: "missing_connect_account" };
        }

        // Sacar chargeId para source_transaction
        let chargeId = null;
        const lc = paymentIntentObj?.latest_charge;
        if (typeof lc === "string" && lc) chargeId = lc;
        if (!chargeId && lc && typeof lc === "object" && lc.id) chargeId = lc.id;

        if (!chargeId && paymentIntentObj?.charges?.data?.length) {
          chargeId = paymentIntentObj.charges.data[0]?.id || null;
        }

        if (!chargeId) {
          await sessionRef.set(
            {
              transferStatus: "missing_charge_id",
              transferUpdatedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          return { skipped: true, reason: "missing_charge_id" };
        }

        const grossCapturedCents = asInt(capturedAmountCents || 0);
        if (grossCapturedCents <= 0) {
          return { skipped: true, reason: "zero_amount" };
        }

        // Comisión plataforma
        const feeCents = Math.max(0, Math.min(
          grossCapturedCents,
          Math.round((grossCapturedCents * PLATFORM_FEE_BPS) / 10000)
        ));

        // Neto a compañera
        const netToCompanionCents = Math.max(0, grossCapturedCents - feeCents);

        if (netToCompanionCents <= 0) {
          await sessionRef.set(
            {
              transferStatus: "zero_after_fee",
              transferUpdatedAt: FieldValue.serverTimestamp(),
              platformFeeBps: PLATFORM_FEE_BPS,
              platformFeeAmountCents: feeCents,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          return { skipped: true, reason: "zero_after_fee" };
        }

        // ✅ TRANSFER A CONNECT
        const transfer = await stripe.transfers.create({
          amount: netToCompanionCents,
          currency,
          destination: destinationAccountId,
          source_transaction: chargeId,
          transfer_group: `session_${sessionId}`,
          metadata: {
            sessionId,
            paymentIntentId,
            speakerId,
            companionId,
          },
        });

        await sessionRef.set(
          {
            transferId: transfer.id,
            transferAmountCents: netToCompanionCents,
            platformFeeBps: PLATFORM_FEE_BPS,
            platformFeeAmountCents: feeCents,
            grossCapturedAmountCents: grossCapturedCents,
            transferCurrency: currency,
            transferStatus: "created",
            transferCreatedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return { ok: true, transferId: transfer.id, transferAmountCents };
      };

      // ✅ Si ya estaba capturado, igual intentamos crear el transfer si faltó (repair)
      if (session.paymentCaptured === true) {
        const piAlready = await stripe.paymentIntents.retrieve(paymentIntentId, {
          expand: ["latest_charge", "charges.data"],
        });

        const capturedAmountCents = asInt(session.capturedAmountCents || piAlready.amount_received || 0);
        const transferResult = await maybeCreateTransfer(piAlready, capturedAmountCents);

        return {
          ok: true,
          alreadyCaptured: true,
          capturedAmountCents,
          paymentIntentStatus: (session.paymentIntentStatus || piAlready.status || "").toString(),
          transfer: transferResult,
        };
      }

      // 1) Estado actual del PI
      let pi;
      try {
        pi = await stripe.paymentIntents.retrieve(paymentIntentId, {
          expand: ["latest_charge", "charges.data"],
        });
      } catch (err) {
        const msg =
          err && err.raw && err.raw.message ? err.raw.message : err?.message || String(err);
        throw new HttpsError("failed-precondition", `No se pudo leer PaymentIntent: ${msg}`);
      }

      // Ya capturado en Stripe
      if (pi.status === "succeeded") {
        const receivedCents = asInt(pi.amount_received || pi.amount || holdAmountCents);

        await sessionRef.set(
          {
            paymentCaptured: true,
            capturedAmountCents: receivedCents,
            capturedAt: FieldValue.serverTimestamp(),
            paymentIntentStatus: pi.status,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        const transferResult = await maybeCreateTransfer(pi, receivedCents);

        return {
          ok: true,
          alreadyCaptured: true,
          paymentIntentStatus: pi.status,
          capturedAmountCents: receivedCents,
          transfer: transferResult,
        };
      }

      if (pi.status === "canceled") {
        throw new HttpsError("failed-precondition", "PaymentIntent está canceled.");
      }

      if (pi.status !== "requires_capture") {
        throw new HttpsError(
          "failed-precondition",
          `PaymentIntent en estado inesperado: ${pi.status}`
        );
      }

      // 2) Capturar
      try {
        const captured = await stripe.paymentIntents.capture(paymentIntentId, {
          amount_to_capture: amountToCapture,
          expand: ["latest_charge", "charges.data"],
        });

        const receivedCents = asInt(captured.amount_received || amountToCapture);

        await sessionRef.set(
          {
            paymentCaptured: true,
            capturedAmountCents: receivedCents,
            capturedAt: FieldValue.serverTimestamp(),
            paymentIntentStatus: captured.status,
            captureEndedBy: endedBy,
            captureBillingMinutes: billingMinutes,
            captureDurationMinutes: durationMinutes,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        // ✅ Transfer a Connect (si aplica)
        const transferResult = await maybeCreateTransfer(captured, receivedCents);

        return {
          ok: true,
          paymentIntentStatus: captured.status,
          capturedAmountCents: receivedCents,
          amountToCapture,
          billingMinutes,
          durationMinutes,
          endedBy,
          transfer: transferResult,
        };
      } catch (err) {
        const msg =
          err && err.raw && err.raw.message ? err.raw.message : err?.message || String(err);

        // Si por carrera ya se capturó, lo tratamos como OK + intentamos transfer
        if (String(msg).toLowerCase().includes("already") && String(msg).toLowerCase().includes("captur")) {
          const pi2 = await stripe.paymentIntents.retrieve(paymentIntentId, {
            expand: ["latest_charge", "charges.data"],
          });

          const receivedCents = asInt(pi2.amount_received || pi2.amount || holdAmountCents);

          await sessionRef.set(
            {
              paymentCaptured: true,
              capturedAmountCents: receivedCents,
              capturedAt: FieldValue.serverTimestamp(),
              paymentIntentStatus: pi2.status,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          const transferResult = await maybeCreateTransfer(pi2, receivedCents);

          return {
            ok: true,
            alreadyCaptured: true,
            paymentIntentStatus: pi2.status,
            capturedAmountCents: receivedCents,
            transfer: transferResult,
          };
        }

        throw new HttpsError("failed-precondition", `Capture falló: ${msg}`);
      }
    }
  );

  // ============================================================
  // STRIPE CONNECT (EXPRESS) - Companions (MXN / MX)
  // ============================================================

  exports.connect_createExpressAccount = onCall(
    { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
    async (request) => {
      if (!request.auth) throw new HttpsError("unauthenticated", "Auth requerida.");

      const uid = request.auth.uid;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data() || {};

      // Si ya existe, regresamos
      const existing = (user.stripeConnectAccountId || "").toString().trim();
      if (existing) return { ok: true, already: true, accountId: existing };

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      // Email (si existe en token)
      const email = (request.auth.token?.email || "").toString().trim() || undefined;

      try {
        const account = await stripe.accounts.create({
          type: "express",
          country: "MX",
          email,
          capabilities: {
            transfers: { requested: true }, // ✅ para recibir transfers
          },
          metadata: { firebaseUid: uid, app: "lissen" },
        });

        await userRef.set(
          {
            stripeConnectAccountId: account.id,
            stripeConnectCreatedAt: FieldValue.serverTimestamp(),
            stripeConnectUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return { ok: true, accountId: account.id };
      } catch (err) {
        const msg =
          err && err.raw && err.raw.message ? err.raw.message : err?.message || String(err);
        throw new HttpsError("failed-precondition", `No se pudo crear cuenta Connect: ${msg}`);
      }
    }
  );

  exports.connect_createOnboardingLink = onCall(
    { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
    async (request) => {
      if (!request.auth) throw new HttpsError("unauthenticated", "Auth requerida.");

      const uid = request.auth.uid;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data() || {};

      let accountId = (user.stripeConnectAccountId || "").toString().trim();

      // Si no existe, la creamos aquí mismo para simplificarte el flujo
      if (!accountId) {
        const stripe = require("stripe")(STRIPE_SECRET_KEY.value());
        const email = (request.auth.token?.email || "").toString().trim() || undefined;

        const account = await stripe.accounts.create({
          type: "express",
          country: "MX",
          email,
          capabilities: { transfers: { requested: true } },
          metadata: { firebaseUid: uid, app: "lissen" },
        });

        accountId = account.id;

        await userRef.set(
          {
            stripeConnectAccountId: accountId,
            stripeConnectCreatedAt: FieldValue.serverTimestamp(),
            stripeConnectUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      // ⚠️ Stripe exige HTTPS.
      // Por ahora usa Firebase Hosting (aunque sea una página vacía). Luego lo refinamos.
      const returnUrl =
        (request.data?.returnUrl || "").toString().trim() || "https://lissen-mvp.web.app/stripe-return";
      const refreshUrl =
        (request.data?.refreshUrl || "").toString().trim() || "https://lissen-mvp.web.app/stripe-refresh";

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      try {
        const link = await stripe.accountLinks.create({
          account: accountId,
          refresh_url: refreshUrl,
          return_url: returnUrl,
          type: "account_onboarding",
        });

        // Guardamos que inició onboarding (opcional)
        await userRef.set(
          {
            stripeConnectOnboardingStartedAt: FieldValue.serverTimestamp(),
            stripeConnectUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return { ok: true, accountId, url: link.url };
      } catch (err) {
        const msg =
          err && err.raw && err.raw.message ? err.raw.message : err?.message || String(err);
        throw new HttpsError("failed-precondition", `No se pudo crear onboarding link: ${msg}`);
      }
    }
  );

  exports.connect_getAccountStatus = onCall(
    { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
    async (request) => {
      if (!request.auth) throw new HttpsError("unauthenticated", "Auth requerida.");

      const uid = request.auth.uid;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data() || {};

      const accountId = (user.stripeConnectAccountId || "").toString().trim();
      if (!accountId) {
        throw new HttpsError("failed-precondition", "No hay stripeConnectAccountId en el usuario.");
      }

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      try {
        const acct = await stripe.accounts.retrieve(accountId);

        const detailsSubmitted = !!acct.details_submitted;
        const payoutsEnabled = !!acct.payouts_enabled;
        const chargesEnabled = !!acct.charges_enabled; // no lo necesitamos ahorita, pero sirve para status

        await userRef.set(
          {
            stripeConnectDetailsSubmitted: detailsSubmitted,
            stripeConnectPayoutsEnabled: payoutsEnabled,
            stripeConnectChargesEnabled: chargesEnabled,
            stripeConnectUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return {
          ok: true,
          accountId,
          detailsSubmitted,
          payoutsEnabled,
          chargesEnabled,
        };
      } catch (err) {
        const msg =
          err && err.raw && err.raw.message ? err.raw.message : err?.message || String(err);
        throw new HttpsError("failed-precondition", `No se pudo leer cuenta Connect: ${msg}`);
      }
    }
  );

  exports.connect_createLoginLink = onCall(
    { region: "us-central1", secrets: [STRIPE_SECRET_KEY] },
    async (request) => {
      if (!request.auth) throw new HttpsError("unauthenticated", "Auth requerida.");

      const uid = request.auth.uid;
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data() || {};

      const accountId = (user.stripeConnectAccountId || user.stripeAccountId || "").toString().trim();
      if (!accountId) {
        throw new HttpsError("failed-precondition", "No tienes cuenta Connect vinculada.");
      }

      const stripe = require("stripe")(STRIPE_SECRET_KEY.value());

      // Login link para Express Dashboard
      const link = await stripe.accounts.createLoginLink(accountId);

      return { ok: true, url: link.url };
    }
  );
  
  exports.livekitGetToken = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Login required");
  }

  const sessionId = String(request.data?.sessionId ?? "");
  const callType = String(request.data?.callType ?? "voice"); // "voice" | "video"

  if (!sessionId) {
    throw new HttpsError("invalid-argument", "Missing sessionId");
  }
  if (callType !== "voice" && callType !== "video") {
    throw new HttpsError("invalid-argument", "Invalid callType");
  }

  const db = getFirestore();
  const snap = await db.collection("sessions").doc(sessionId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Session not found");
  }

  const s = snap.data() || {};
  const status = String(s.status ?? "active");
  if (status !== "active") {
    throw new HttpsError("failed-precondition", "Session is not active");
  }

  const speakerId = String(s.speakerId ?? "");
  const companionId = String(s.companionId ?? "");
  if (uid !== speakerId && uid !== companionId) {
    throw new HttpsError("permission-denied", "Not a session participant");
  }

  // ✅ Validación mínima de "pago OK" (hold autorizado)
  const paymentIntentId = s.paymentIntentId;
  const holdAuthorizedAt = s.holdAuthorizedAt;
  if (!paymentIntentId || !holdAuthorizedAt) {
    throw new HttpsError("failed-precondition", "Payment hold not authorized");
  }

  // ✅ Permisos por oferta (flags en session)
  const communicationType = String(s.communicationType ?? "chat");
  const canVoice =
    (s.canVoice ?? (communicationType === "voice" || communicationType === "video")) === true;
  const canVideo =
    (s.canVideo ?? (communicationType === "video")) === true;

  if (callType === "voice" && !canVoice) {
    throw new HttpsError("failed-precondition", "Voice not allowed");
  }
  if (callType === "video" && !canVideo) {
    throw new HttpsError("failed-precondition", "Video not allowed");
  }

  const LIVEKIT_URL = process.env.LIVEKIT_URL;
  const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
  const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;

  if (!LIVEKIT_URL || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    throw new HttpsError("failed-precondition", "LiveKit env not configured");
  }

  const token = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
    identity: uid,
    name: String(s[uid === speakerId ? "speakerAlias" : "companionAlias"] ?? uid),
  });

  token.addGrant({
    roomJoin: true,
    room: sessionId,
    canPublish: true,
    canSubscribe: true,
  });

  return {
    url: LIVEKIT_URL,
    token: await token.toJwt(),
    room: sessionId,
    callType,
  };
});


