# Diagnostic Splunk - Extraction des champs

## Problème
Les champs `service` et `level` ne s'affichent pas dans les résultats Splunk malgré qu'ils existent dans les logs JSON.

## Étape 1 : Vérifier la structure brute

Exécutez cette requête dans Splunk pour voir la structure exacte :

```splunk
index=mcp-logs "3d7fc6c5-cd75-433c-9f12-cf3ea5f3895b"
  | head 1
  | table _raw
```

## Étape 2 : Lister tous les champs disponibles

```splunk
index=mcp-logs "3d7fc6c5-cd75-433c-9f12-cf3ea5f3895b"
  | head 1
  | fieldsummary
  | table field
```

## Étape 3 : Test extraction avec spath

```splunk
index=mcp-logs "3d7fc6c5-cd75-433c-9f12-cf3ea5f3895b"
  | head 5
  | spath
  | table service level message event correlationId clientId
```

## Étape 4 : Si spath ne marche pas, extraction manuelle depuis _raw

```splunk
index=mcp-logs "3d7fc6c5-cd75-433c-9f12-cf3ea5f3895b"
  | head 5
  | rex field=_raw "\"service\":\"(?<service_extracted>[^\"]+)\""
  | rex field=_raw "\"level\":\"(?<level_extracted>[^\"]+)\""
  | rex field=_raw "\"message\":\"(?<message_extracted>[^\"]+)\""
  | table service service_extracted level level_extracted message message_extracted
```

## Solution probable

Si Splunk HEC envoie les données dans un format spécial, les champs peuvent être préfixés ou imbriqués.

Essayez cette requête corrigée :

```splunk
index=mcp-logs "3d7fc6c5-cd75-433c-9f12-cf3ea5f3895b"
  | spath
  | rex field=_raw "\"service\":\"(?<service_name>[^\"]+)\""
  | rex field=_raw "\"level\":\"(?<level_name>[^\"]+)\""
  | eval service_final=coalesce(service, service_name, "inconnu")
  | eval level_final=coalesce(level, level_name, "INFO")
  | eval timestamp=strftime(_time, "%H:%M:%S.%3N")
  | rex field=message "event=(?<event_msg>[A-Z_]+)"
  | eval event_type=coalesce(event, event_msg)
  | rex field=message "function=(?<function>\w+)"
  | rex field=message "phoneNumber=(?<phoneNumber>[+0-9*]+)"
  | rex field=message "changeCount=(?<changeCount>\d+)"
  | rex field=message "isSuspicious=(?<isSuspicious>\w+)"
  | rex field=message "suspicionScore=(?<suspicionScore>[0-9.]+)"
  | eval etape=case(
      event_type=="PHONE_UPDATE_DEMANDE_RECUE" OR event=="DEMANDE_PHONE_RECUE", "01 - 📱 Demande reçue",
      event_type=="ORCHESTRATION_DEMARREE" OR event=="ORCHESTRATION_PHONE_DEMARREE", "02 - 🚀 Orchestration démarrée",
      event_type=="LAMBDA_INVOQUEE" AND match(message, "ReadClientProfileLambda"), "03 - 👤 Lecture profil client",
      event_type=="LAMBDA_INVOQUEE" AND match(message, "PhoneValidatorLambda"), "05 - 🔍 Validation E.164",
      event_type=="LAMBDA_INVOQUEE" AND match(message, "CheckPhoneHistoryLambda"), "07 - 📋 Vérif historique",
      event_type=="PHONE_HISTORY_CHECKED", "08 - 📊 Historique analysé",
      event_type=="LAMBDA_INVOQUEE" AND match(message, "HumanApprovalLambda"), "09 - 🔔 Eval approbation",
      true(), ""
  )
  | where isnotnull(etape) AND etape!=""
  | sort _time
  | table timestamp etape service_final level_final function clientId changeCount isSuspicious suspicionScore message
```

## Vérification des champs disponibles

Pour voir tous les champs que Splunk a extrait automatiquement :

```splunk
index=mcp-logs "3d7fc6c5-cd75-433c-9f12-cf3ea5f3895b"
  | head 1
  | transpose
```

Cette commande affichera tous les champs avec leur valeur dans une liste verticale.