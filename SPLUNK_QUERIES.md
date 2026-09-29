# Guide Splunk - Requêtes pour Suivi des Workflows MCP

**Date** : 2026-09-25
**Splunk UI** : http://localhost:8000
**Credentials** : admin / Admin123!

---

## 🔍 Accès Splunk

### 1. Connexion
```
URL : http://localhost:8000
Username : admin
Password : Admin123!
```

### 2. Navigation
1. Cliquer sur **"Search & Reporting"** (icône en haut à gauche)
2. Entrer votre requête dans la barre de recherche
3. Sélectionner la période (Last 15 minutes, Last hour, etc.)
4. Cliquer sur **"Search"**

---

## 📊 Requêtes par Workflow

### 🔹 Workflow Phone Update - Toutes les Étapes

Cette requête trace le parcours complet d'une demande de changement de téléphone :

```splunk
index=mcp-logs "VOTRE_CORRELATION_ID"
  | spath
  | eval timestamp=strftime(_time, "%H:%M:%S.%3N")
  | eval service=case(
      match(logger_name, "com\.bnc\.mcp\.api\."), "mcp-api",
      match(logger_name, "com\.bnc\.mcp\.orchestration\."), "mcp-orchestration",
      match(source, "mcp-api"), "mcp-api",
      match(source, "mcp-orchestration"), "mcp-orchestration",
      true(), "unknown"
  )
  | eval msg=message
  | rex field=msg "event=(?<event>[A-Z_]+)"
  | rex field=msg "function=(?<function>\w+)"
  | rex field=msg "clientId=(?<clientId>\d+)"
  | rex field=msg "phoneNumber=(?<phoneNumber>[+0-9*]+)"
  | rex field=msg "score=(?<score>[0-9.]+)"
  | rex field=msg "changeCount=(?<changeCount>\d+)"
  | rex field=msg "isSuspicious=(?<isSuspicious>\w+)"
  | rex field=msg "otpId=(?<otpId>[a-zA-Z0-9-]+)"
  | eval etape=case(
      event=="DEMANDE_PHONE_RECUE", "01 - 📱 Demande reçue",
      event=="STATE_MACHINE_PHONE_UPDATE_RESOLUE", "02 - 🔍 State machine résolue",
      event=="ORCHESTRATION_PHONE_DEMARREE", "03 - 🚀 Orchestration démarrée",
      event=="LAMBDA_INVOQUEE" AND function=="ReadClientProfileLambda", "04 - 👤 Lecture profil",
      event=="LAMBDA_SUCCESS" AND function=="ReadClientProfileLambda", "05 - ✅ Profil chargé",
      event=="LAMBDA_INVOQUEE" AND function=="PhoneValidatorLambda", "06 - 🔍 Validation E.164",
      event=="PHONE_VALIDATED", "07 - ✅ Format E.164 valide",
      event=="LAMBDA_SUCCESS" AND function=="PhoneValidatorLambda", "08 - ✅ Validation OK",
      event=="LAMBDA_INVOQUEE" AND function=="CheckPhoneHistoryLambda", "09 - 📋 Vérif historique",
      event=="PHONE_HISTORY_CHECKED", "10 - 📊 Historique analysé",
      event=="LAMBDA_SUCCESS" AND function=="CheckPhoneHistoryLambda", "11 - ✅ Historique OK",
      event=="LAMBDA_INVOQUEE" AND function=="HumanApprovalLambda", "12 - 🔔 Éval approbation",
      isSuspicious=="true", "13 - ⚠️ SUSPICION DÉTECTÉE",
      isSuspicious=="false", "13 - ✅ Pas suspicion",
      event=="LAMBDA_SUCCESS" AND function=="HumanApprovalLambda", "14 - ✅ Éval terminée",
      event=="LAMBDA_INVOQUEE" AND function=="SendOTPSMSLambda", "15 - 📲 Envoi OTP SMS",
      event=="OTP_GENERATED", "16 - 🔐 OTP généré",
      event=="OTP_SMS_SENT", "17 - ✅ SMS envoyé",
      event=="LAMBDA_SUCCESS" AND function=="SendOTPSMSLambda", "18 - ✅ OTP envoyé",
      event=="LAMBDA_INVOQUEE" AND function=="CheckOTPStatusLambda", "19 - 🔍 Vérif OTP",
      event=="OTP_VALIDATION_STATUS", "20 - 📊 Statut OTP",
      event=="OTP_VALIDATED", "21 - ✅ OTP validé",
      event=="OTP_EXPIRED", "21 - ⏰ OTP expiré",
      event=="OTP_MAX_ATTEMPTS", "21 - ⛔ Tentatives max",
      event=="LAMBDA_SUCCESS" AND function=="CheckOTPStatusLambda", "22 - ✅ Vérif OTP OK",
      event=="LAMBDA_INVOQUEE" AND function=="PhoneMDMAEClientLambda", "23 - 🔄 Update MDMAE",
      event=="MDMAE_PHONE_UPDATE_STARTED", "24 - 🚀 MDMAE démarré",
      event=="MDMAE_PHONE_UPDATE_SUCCESS", "25 - ✅ MDMAE mis à jour",
      event=="LAMBDA_SUCCESS" AND function=="PhoneMDMAEClientLambda", "26 - ✅ MDMAE OK",
      event=="LAMBDA_INVOQUEE" AND function=="FCCSenderLambda", "27 - 📤 Envoi FCC",
      event=="KAFKA_MESSAGE_SENT", "28 - 📨 Kafka envoyé",
      event=="LAMBDA_SUCCESS" AND function=="FCCSenderLambda", "29 - ✅ FCC envoyé",
      event=="LAMBDA_INVOQUEE" AND function=="CRMUpdaterLambda", "30 - 🔄 Update CRM",
      event=="CRM_UPDATE_STARTED", "31 - 🚀 CRM démarré",
      event=="CRM_UPDATE_SUCCESS", "32 - ✅ CRM mis à jour",
      event=="LAMBDA_SUCCESS" AND function=="CRMUpdaterLambda", "33 - ✅ CRM OK",
      event=="LAMBDA_INVOQUEE" AND function=="NotificationUpdaterLambda", "34 - 🔔 Update notifs",
      event=="NOTIFICATION_UPDATE_STARTED", "35 - 🚀 Notif démarrée",
      event=="NOTIFICATION_UPDATE_SUCCESS", "36 - ✅ Notif mise à jour",
      event=="LAMBDA_SUCCESS" AND function=="NotificationUpdaterLambda", "37 - ✅ Notif OK",
      event=="LAMBDA_INVOQUEE" AND function=="NotificationSenderLambda", "38 - 📧 Envoi email",
      event=="EMAIL_SENT", "39 - ✅ Email envoyé",
      event=="LAMBDA_SUCCESS" AND function=="NotificationSenderLambda", "40 - ✅ Email OK",
      event=="LAMBDA_INVOQUEE" AND function=="RecordPhoneHistoryLambda", "41 - 💾 Enreg historique",
      event=="PHONE_HISTORY_RECORDED", "42 - 💾 Historique sauvé",
      event=="LAMBDA_SUCCESS" AND function=="RecordPhoneHistoryLambda", "43 - ✅ Historique OK",
      event=="PHONE_UPDATE_SUCCESS", "45 - 🎉 SUCCÈS COMPLET",
      level=="ERROR", "99 - ❌ ERREUR",
      true(), event
  )
  | where isnotnull(etape) AND etape!=""
  | sort _time
  | table timestamp etape service level function clientId phoneNumber score changeCount isSuspicious otpId msg
```

**Comment l'utiliser** :
1. Remplacez `VOTRE_CORRELATION_ID` par le vrai correlationId de votre demande
2. Exemple : Si votre réponse API contient `"correlationId": "e1a20023-d0f6-4c9b-975e-331007ad4aca"`
3. La requête devient : `index=mcp-logs ("correlationId=e1a20023-d0f6-4c9b-975e-331007ad4aca"`

---

### 🔹 Workflow Name Update - Toutes les Étapes

```splunk
index=mcp-logs "VOTRE_CORRELATION_ID"
  | spath
  | eval timestamp=strftime(_time, "%H:%M:%S.%3N")
  | eval service=case(
      match(logger_name, "com\.bnc\.mcp\.api\."), "mcp-api",
      match(logger_name, "com\.bnc\.mcp\.orchestration\."), "mcp-orchestration",
      match(logger_name, "com\.bnc\.mcp\.fcc\."), "mcp-fcc-connector",
      match(source, "mcp-api"), "mcp-api",
      match(source, "mcp-orchestration"), "mcp-orchestration",
      match(source, "mcp-fcc-connector"), "mcp-fcc-connector",
      true(), "unknown"
  )
  | eval msg=message
  | rex field=msg "event=(?<event>[A-Z_]+)"
  | rex field=msg "function=(?<function>\w+)"
  | rex field=msg "score=(?<score>[0-9.]+)"
  | rex field=msg "statut=(?<statut>\w+)"
  | rex field=msg "erreur=(?<erreur>[^\"]+)"
  | rex field=msg "clientId=(?<clientId>\d+)"
  | eval etape=case(
      event=="DEMANDE_RECUE", "01 - 📝 Demande reçue",
      event=="ORCHESTRATION_DEMARREE", "02 - 🚀 Orchestration démarrée",
      event=="LAMBDA_INVOQUEE" AND function=="ValidationLambda", "03 - 🔍 Validation demandée",
      event=="VALIDATION_REUSSIE", "04 - ✅ Validation OK",
      event=="VALIDATION_ECHOUEE", "04 - ❌ Validation ÉCHOUÉE",
      event=="LAMBDA_ECHEC" AND function=="ValidationLambda", "04 - ❌ Validation ÉCHOUÉE",
      event=="LAMBDA_TERMINEE" AND function=="ValidationLambda", "05 - ✅ Lambda validation OK",
      event=="LAMBDA_INVOQUEE" AND function=="MatchingLambda", "06 - 🔎 Matching demandé",
      event=="MATCHING_TERMINE", "07 - 📊 Matching terminé (score: " + score + ")",
      event=="LAMBDA_TERMINEE" AND function=="MatchingLambda", "08 - ✅ Lambda matching OK",
      event=="REVUE_HUMAINE_EN_ATTENTE", "09 - ⏸️ EN ATTENTE VALIDATION AGENT",
      event=="DECISION_ENREGISTREE" AND statut=="REJECTED", "10 - ❌ Décision REJETÉE",
      event=="DECISION_ENREGISTREE" AND statut=="APPROVED", "10 - ✅ Décision APPROUVÉE",
      event=="DECISION_ENREGISTREE", "10 - ✅ Décision enregistrée",
      event=="LAMBDA_INVOQUEE" AND function=="UpdateProfileLambda", "11 - 🔄 MAJ profil demandée",
      event=="PROFIL_MIS_A_JOUR", "12 - ✅ Profil DynamoDB mis à jour",
      event=="LAMBDA_TERMINEE" AND function=="UpdateProfileLambda", "13 - ✅ Lambda profil OK",
      event=="LAMBDA_INVOQUEE" AND function=="PublishEventLambda", "14 - 📤 Publication demandée",
      event=="EVENEMENT_PUBLIE", "15 - ✅ Événement Kafka publié",
      event=="LAMBDA_TERMINEE" AND function=="PublishEventLambda", "16 - ✅ Lambda publication OK",
      event=="EVENEMENT_KAFKA_CONSOMME", "17 - 📥 Kafka consommé par FCC",
      event=="MESSAGE_DEPOSE_SUR_MQ", "18 - 📬 Message MQ déposé",
      event=="FCC_DEMANDE_RECUE", "19 - 📨 FCC demande reçue",
      event=="FCC_TRAITEMENT_TERMINE", "20 - ✅ FCC traitement terminé",
      event=="FCC_MISE_A_JOUR_CONFIRMEE", "21 - ✅ FCC MAJ confirmée",
      event=="ORCHESTRATION_NOTIFIE", "22 - 🔔 Orchestration notifiée",
      event=="NOTIFICATION_FCC_RECUE", "23 - 📨 Notification FCC reçue",
      event=="REPONSE_ENVOYEE", "24 - 🎉 SUCCÈS COMPLET",
      like(event, "%ECHEC%"), "99 - ❌ ÉCHEC",
      like(event, "%ERROR%"), "99 - ❌ ERREUR",
      level=="ERROR", "99 - ❌ ERREUR",
      true(), event
  )
  | where isnotnull(etape) AND etape!=""
  | sort _time
  | table timestamp etape service level function clientId score statut erreur msg
```

---

### 🔹 Vue d'Ensemble - Toutes les Demandes (Dernière Heure)

```splunk
index=mcp-logs event IN ("PHONE_UPDATE_DEMANDE_RECUE", "DEMANDE_RECUE", "ADDRESS_UPDATE_DEMANDE_RECUE")
  | spath
  | eval timestamp=strftime(_time, "%Y-%m-%d %H:%M:%S")
  | eval workflow=case(
      event=="PHONE_UPDATE_DEMANDE_RECUE", "📱 Phone Update",
      event=="DEMANDE_RECUE", "📝 Name Update",
      event=="ADDRESS_UPDATE_DEMANDE_RECUE", "🏠 Address Update",
      true(), "Unknown"
  )
  | rex field=message "correlationId=(?<correlationId>[a-f0-9-]+)"
  | rex field=message "clientId=(?<clientId>\d+)"
  | table timestamp workflow clientId correlationId
  | sort - _time
```

**Utilisation** : Voir toutes les demandes récentes avec leur correlationId pour ensuite tracer une demande spécifique.

---

### 🔹 Suivi Temps Réel - Dernières 5 Minutes

```splunk
index=mcp-logs earliest=-5m
  | spath
  | eval timestamp=strftime(_time, "%H:%M:%S")
  | eval service=coalesce(service, 'message.service')
  | eval level=coalesce(level, 'message.level')
  | eval msg=coalesce(message, 'message.message')
  | rex field=msg "correlationId=(?<correlationId>[a-f0-9-]+)"
  | rex field=msg "clientId=(?<clientId>\d+)"
  | table timestamp service level correlationId clientId msg
  | sort - _time
```

---

### 🔹 Erreurs Uniquement

```splunk
index=mcp-logs level=ERROR earliest=-1h
  | spath
  | eval timestamp=strftime(_time, "%Y-%m-%d %H:%M:%S")
  | eval service=coalesce(service, 'message.service')
  | eval msg=coalesce(message, 'message.message')
  | rex field=msg "correlationId=(?<correlationId>[a-f0-9-]+)"
  | rex field=msg "clientId=(?<clientId>\d+)"
  | rex field=msg "erreur=(?<erreur>[^\"]+)"
  | table timestamp service correlationId clientId erreur msg
  | sort - _time
```

---

### 🔹 Performance - Durée par Étape Lambda

```splunk
index=mcp-logs ("LAMBDA_INVOQUEE" OR "LAMBDA_TERMINE")
  | spath
  | eval correlationId=coalesce(correlationId, 'properties.correlationId')
  | rex field=message "function=(?<lambda_name>\w+)"
  | rex field=message "durationMs=(?<duration_ms>\d+)"
  | stats avg(duration_ms) as avg_duration_ms, max(duration_ms) as max_duration_ms, min(duration_ms) as min_duration_ms by lambda_name
  | eval avg_duration_s=round(avg_duration_ms/1000, 2)
  | eval max_duration_s=round(max_duration_ms/1000, 2)
  | eval min_duration_s=round(min_duration_ms/1000, 2)
  | table lambda_name avg_duration_s max_duration_s min_duration_s
  | sort - avg_duration_s
```

---

### 🔹 Taux de Succès par Workflow (Dernières 24h)

```splunk
index=mcp-logs (event="PHONE_UPDATE_SUCCESS" OR event="PHONE_UPDATE_FAILED" OR event="ORCHESTRATION_ECHOUEE")
  earliest=-24h
  | spath
  | eval success=if(event=="PHONE_UPDATE_SUCCESS", 1, 0)
  | eval failed=if(event=="PHONE_UPDATE_FAILED" OR event=="ORCHESTRATION_ECHOUEE", 1, 0)
  | stats sum(success) as total_success, sum(failed) as total_failed
  | eval total=total_success + total_failed
  | eval success_rate=round((total_success/total)*100, 2)
  | table total total_success total_failed success_rate
```

---

### 🔹 Détection Fraude - Changements Suspects

```splunk
index=mcp-logs event="PHONE_HISTORY_CHECKED"
  | spath
  | rex field=message "suspicionScore=(?<suspicionScore>\d+)"
  | where suspicionScore > 50
  | rex field=message "correlationId=(?<correlationId>[a-f0-9-]+)"
  | rex field=message "clientId=(?<clientId>\d+)"
  | rex field=message "changeCount=(?<changeCount>\d+)"
  | eval timestamp=strftime(_time, "%Y-%m-%d %H:%M:%S")
  | table timestamp clientId correlationId suspicionScore changeCount
  | sort - suspicionScore
```

---

### 🔹 OTP - Statistiques Validation

```splunk
index=mcp-logs (event="OTP_GENERATED" OR event="OTP_STATUS_CHECKED" OR event="OTP_EXPIRED")
  | spath
  | rex field=message "otpId=(?<otpId>[a-f0-9-]+)"
  | rex field=message "validated=(?<validated>\w+)"
  | rex field=message "expired=(?<expired>\w+)"
  | eval timestamp=strftime(_time, "%H:%M:%S")
  | table timestamp event otpId validated expired
  | sort _time
```

---

## 📈 Dashboards Recommandés

### Dashboard 1 : Monitoring Temps Réel

**Panels** :
1. **Demandes par minute** (timechart)
2. **Taux d'erreur** (gauge)
3. **Durée moyenne workflow** (single value)
4. **Logs récents** (table)

**Requête Panel 1** :
```splunk
index=mcp-logs event IN ("PHONE_UPDATE_DEMANDE_RECUE", "DEMANDE_RECUE")
  | timechart count span=1m by event
```

### Dashboard 2 : Suivi Qualité

**Panels** :
1. **Taux de succès** (pie chart)
2. **Top erreurs** (bar chart)
3. **Performance Lambdas** (table)
4. **Détections fraude** (table)

---

## 🎯 Procédure de Troubleshooting

### Étape 1 : Obtenir le correlationId

Quand vous créez une demande, notez le correlationId retourné :

```bash
curl -X POST http://localhost:8080/api/v1/clients/12345/phone \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "+15149876543",
    "country": "CA",
    "reason": "CLIENT_REQUEST",
    "source": "web-portal"
  }'

# Réponse :
{
  "correlationId": "e1a20023-d0f6-4c9b-975e-331007ad4aca",  ← NOTEZ CECI !
  "executionArn": "arn:aws:states:...",
  "statut": "EN_COURS"
}
```

### Étape 2 : Tracer le Workflow dans Splunk

1. Aller sur http://localhost:8000
2. Se connecter (admin / Admin123!)
3. Cliquer sur "Search & Reporting"
4. Coller la requête Phone Update complète
5. Remplacer `VOTRE_CORRELATION_ID` par votre vrai correlationId
6. Cliquer "Search"

### Étape 3 : Identifier le Problème

Regardez la colonne **etape** :
- ✅ Étapes avec checkmark → OK
- ❌ Étapes avec X → ÉCHEC
- ⏸️ Étapes avec pause → EN ATTENTE

Regardez la colonne **erreur** pour le message d'erreur détaillé.

### Étape 4 : Visualisation Timeline

Pour une vue timeline graphique :

```splunk
index=mcp-logs correlationId="VOTRE_CORRELATION_ID"
  | transaction correlationId
  | chart count by _time event
```

---

## 🔧 Configuration Splunk (Déjà Fait)

### Index Configuration

L'index `mcp-logs` est configuré pour recevoir les logs via HTTP Event Collector (HEC).

**Token HEC** : `12345678-1234-1234-1234-123456789012`
**Endpoint** : http://localhost:8088/services/collector

### Retention Policy

Par défaut : **7 jours** (configurable dans Settings → Indexes)

---

## 💡 Tips & Astuces

### 1. Sauvegarder vos Requêtes

Cliquer sur **"Save As"** → **"Report"** pour réutiliser vos requêtes favorites.

### 2. Alertes Automatiques

Créer une alerte pour être notifié en cas d'erreur :

```splunk
index=mcp-logs level=ERROR
  | stats count
  | where count > 10
```

Puis : **Save As → Alert** → configurer email/webhook.

### 3. Exporter Résultats

En bas de la page de résultats : **Export → CSV** ou **Export → JSON**

### 4. Partager une Recherche

**Save As → Dashboard Panel** pour ajouter à un dashboard partagé avec l'équipe.

---

## 📞 Support

**Splunk UI** : http://localhost:8000
**Username** : admin
**Password** : Admin123!

Pour réinitialiser le mot de passe :
```bash
docker exec -it mcp-splunk /opt/splunk/bin/splunk edit user admin -password NEW_PASSWORD -auth admin:Admin123!
```

---

**Créé par** : Équipe MCP
**Dernière mise à jour** : 2026-09-25