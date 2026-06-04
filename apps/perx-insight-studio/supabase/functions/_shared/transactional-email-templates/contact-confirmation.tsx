import * as React from 'npm:react@18.3.1'
import {
  Body, Container, Head, Heading, Html, Preview, Text, Section, Hr,
} from 'npm:@react-email/components@0.0.22'
import type { TemplateEntry } from './registry.ts'

const SITE_NAME = "PerX"

interface ContactConfirmationProps {
  name?: string
  company?: string
  message?: string
}

const ContactConfirmationEmail = ({ name, company, message }: ContactConfirmationProps) => (
  <Html lang="it" dir="ltr">
    <Head />
    <Preview>Grazie per averci contattato — il team PerX ti risponderà al più presto</Preview>
    <Body style={main}>
      <Container style={container}>
        {/* Gradient top bar */}
        <Section style={gradientBar} />

        {/* Logo area */}
        <Section style={logoSection}>
          <Heading style={logoText}>PerX</Heading>
          <Hr style={logoDivider} />
        </Section>

        {/* Main content */}
        <Section style={contentSection}>
          <Heading style={h1}>
            {name ? `Ciao ${name}! 👋` : 'Grazie per averci contattato! 👋'}
          </Heading>

          <Text style={text}>
            Grazie per il tuo interesse verso <strong>PerX</strong>. Abbiamo ricevuto la tua richiesta e ti contatteremo al più presto per fornirti tutte le informazioni di cui hai bisogno.
          </Text>

          {company && (
            <Section style={companyBox}>
              <Text style={companyLabel}>Studio/Azienda</Text>
              <Text style={companyValue}>{company}</Text>
            </Section>
          )}

          {message && (
            <Section style={messageBox}>
              <Text style={messageLabel}>📩 Il tuo messaggio</Text>
              <Text style={messageValue}>"{message}"</Text>
            </Section>
          )}

          <Hr style={divider} />

          <Text style={signOff}>A presto,</Text>
          <Text style={teamName}>Il Team PerX</Text>
          <Text style={subBrand}>PynkStudio</Text>
        </Section>

        {/* Footer */}
        <Section style={footer}>
          <Text style={footerText}>© 2025 PerX by PynkStudio</Text>
          <Text style={footerSubText}>Tutti i diritti riservati</Text>
        </Section>
      </Container>
    </Body>
  </Html>
)

export const template = {
  component: ContactConfirmationEmail,
  subject: 'Grazie per il tuo interesse in PerX',
  displayName: 'Conferma contatto',
  previewData: { name: 'Marco', company: 'Studio Legale Rossi', message: 'Vorrei sapere di più su PerX per il mio studio.' },
} satisfies TemplateEntry

// Styles
const main = { backgroundColor: '#ffffff', fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif" }

const container = { maxWidth: '600px', margin: '0 auto', backgroundColor: '#ffffff' }

const gradientBar = {
  height: '6px',
  background: 'linear-gradient(135deg, #ff69b4 0%, #9747d8 50%, #ff9933 100%)',
}

const logoSection = {
  padding: '32px 40px 20px',
  textAlign: 'center' as const,
}

const logoText = {
  margin: '0',
  fontSize: '36px',
  fontWeight: '800' as const,
  color: '#1a1f3a',
  letterSpacing: '-1px',
}

const logoDivider = {
  marginTop: '12px',
  width: '60px',
  height: '3px',
  background: 'linear-gradient(90deg, #ff69b4, #9747d8)',
  border: 'none',
  marginLeft: 'auto',
  marginRight: 'auto',
}

const contentSection = { padding: '0 40px 32px' }

const h1 = {
  fontSize: '24px',
  fontWeight: '700' as const,
  color: '#1a1f3a',
  margin: '0 0 20px',
  lineHeight: '1.3',
}

const text = {
  fontSize: '15px',
  color: '#4a4a4a',
  lineHeight: '1.7',
  margin: '0 0 24px',
}

const companyBox = {
  backgroundColor: '#fdf2f8',
  borderLeft: '4px solid #ff69b4',
  padding: '16px 20px',
  borderRadius: '8px',
  marginBottom: '20px',
}

const companyLabel = {
  margin: '0 0 4px',
  fontSize: '12px',
  fontWeight: '600' as const,
  color: '#ff69b4',
  textTransform: 'uppercase' as const,
  letterSpacing: '1px',
}

const companyValue = {
  margin: '0',
  fontSize: '15px',
  fontWeight: '500' as const,
  color: '#1a1f3a',
}

const messageBox = {
  backgroundColor: '#f5f3ff',
  borderRadius: '12px',
  padding: '20px',
  marginBottom: '24px',
  border: '1px solid #e9e5f5',
}

const messageLabel = {
  margin: '0 0 10px',
  fontSize: '12px',
  fontWeight: '700' as const,
  color: '#9747d8',
  textTransform: 'uppercase' as const,
  letterSpacing: '1.5px',
}

const messageValue = {
  margin: '0',
  fontSize: '14px',
  color: '#4a4a4a',
  lineHeight: '1.7',
  fontStyle: 'italic' as const,
}

const divider = {
  borderColor: '#eee',
  margin: '24px 0',
}

const signOff = {
  margin: '0 0 4px',
  fontSize: '14px',
  color: '#6b7280',
}

const teamName = {
  margin: '0',
  fontSize: '16px',
  fontWeight: '700' as const,
  color: '#9747d8',
}

const subBrand = {
  margin: '4px 0 0',
  fontSize: '13px',
  color: '#9ca3af',
  fontWeight: '500' as const,
}

const footer = {
  backgroundColor: '#f9fafb',
  padding: '20px 40px',
  textAlign: 'center' as const,
  borderTop: '1px solid #f0f0f0',
}

const footerText = {
  margin: '0 0 4px',
  fontSize: '12px',
  color: '#9ca3af',
}

const footerSubText = {
  margin: '0',
  fontSize: '11px',
  color: '#d1d5db',
}
