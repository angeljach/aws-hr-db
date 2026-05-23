# Instrucciones
Implementa un proyecto en terraform tomando como referencia la arquitectura definida en el archivo [architecture.png](architecture.png). Ten en cuenta las siguientes consideraciones:
* Genera el proyecto en Terraform que cree la arquitectura en AWS.
* Poseo acceso a AWS Free Tier, trata de ajustar los componentes para que me cueste lo menos posible o se incluya en la capa gratuita. Si detectas que algo excede la capa gratuita, menciónalo.

## Flujo
El flujo general incluye:
* Extracción de información por medio de una lambda
* Cifrado de datos sensibles usando KMS
* Persistencia de la información extraida en una BD de Postgresql en AWS RDS
* Genera 2 endpoints que puedan ser consumidos por diferentes clientes. Uno me permitirá traer todos los empleados de la BD, implementa paginación de 10 en 10. Otro me permitirá traer un solo empleado en base a su PK (número de empleado)
  * GET /employees
  * GET /empoloyees/{id}
* Si bien se tienen solo 2 endpoints, simula la creación de 3 consumidores, los cuales podrán acceder a distinta información.
  * Uno que tenga acceso a toda la información
  * Otro tendrá acceso solo a información no sensible
  * Otro más tendrá acceso a información no sensible más dos campos sensibles
* Propón la forma de implementar los roles esto utilizando Cognito
* Una lambda se deberá encargar de extrer la información en base a los roles definidos anteriormente
* Expón los endpoints para que puedan ser consumidos desde fuera utilizando una herramienta como CURL o Postman
* Origianlmente los secretos deben ser almacenados en Secrets Manager, pero dado que esto puede incurrir en costos, no lo utilices y almacena los datos directamente en las lambdas

## Datos
* No necesito el acceso a Big Query, simula la consulta con datos dummy en la lambda.
* La información a consultar está asociada con información sensible de empleados de una empresa que incluye nombres, direcciones, teléfonos, sueldo. Toma esta información como base para generar los datos dummy.
* Genera 20 registros dummy unicamente para simular la extracción de información. Estos registros deberán ser persistidos en la BD de RDS.
* El PK será el número de empleado. Considérado en la creación
* La arquitectura incluye un apartado de cifrado y descifrado con KMS, tu define los campos en base a la información de prueba que vayas a generar

# Importante
Al ser una prueba de concepto, trata de ajustar los componentes para que el costo de la prueba sea casi 0 en AWS. Si detectas que algo excede la capa gratuita, menciónalo en el plan