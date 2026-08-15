## Use an official Tomcat image as a base image
FROM tomcat:9-jdk17-temurin

LABEL maintainer="github.com/esarath"

## Remove default Tomcat application
RUN rm -rf /usr/local/tomcat/webapps/ROOT/*

## Copy your web application to the Tomcat webapps directory
COPY webapp/ /usr/local/tomcat/webapps/ROOT/

## Change the default shell to bash and run as a non-root user
RUN ln -sf /bin/bash /bin/sh \
    && groupadd -r tomcat && useradd -r -g tomcat tomcat \
    && chown -R tomcat:tomcat /usr/local/tomcat
USER tomcat

## Expose the default Tomcat port
EXPOSE 8080

## Start Tomcat when the container starts
CMD ["catalina.sh", "run"]