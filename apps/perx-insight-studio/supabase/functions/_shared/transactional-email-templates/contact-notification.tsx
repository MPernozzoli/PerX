import * as React from 'npm:react@18.3.1'
import {
  Body, Container, Head, Heading, Html, Preview, Text, Section, Hr,
} from 'npm:@react-email/components@0.0.22'
import type { TemplateEntry } from './registry.ts'

interface ContactNotificationProps {
  name?: string
  email?: string
  company?: string
  message?: string
}

const ContactNotificationEmail = ({ name, email, company, message }: ContactNotificationProps) => (
  <Html lang="it" dir="ltr">
    <Head />
    <Preview>Nuova richiesta di contatto da {name || 'un utente'}</Preview>
    <Body style={main}>
      <Container style={container}>
        <Heading style={h1}>Nuova richiesta di contatto da PerX.it</Heading>

        <Section style={fieldSection}>
          <Text style={label}>Nome</Text>
          <Text style={value}>{name || '-'}</Text>
        </Section>

        <Section style={fieldSection}>
          <Text style={label}>Email</Text>
          <Text style={value}>{email || '-'}</Text>
        </Section>

        {company && (
          <Section style={fieldSection}>
            <Text style={label}>Studio / Azienda</Text>
            <Text style={value}>{company}</Text>
          </Section>
        )}

        <Hr style={divider} />

        <Text style={label}>Messaggio</Text>
        <Section style={messageBox}>
          <Text style={messageText}>{message || '-'}</Text>
        </Section>
      </Container>
    </Body>
  </Html>
)

export const template = {
  component: ContactNotificationEmail,
  subject: (data: Record<string, any>) => `Nuova richiesta informazioni PerX da ${data.name || 'un utente'}`,
  displayName: 'Notifica contatto al team',
  to: 'info@perx.it',
  previewData: { name: 'Marco Rossi', email: 'marco@example.com', company: 'Studio Legale Rossi', message: 'Vorrei sapere di più su PerX.' },
} satisfies TemplateEntry

const main = { backgroundColor: '#ffffff', fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif" }
const container = { maxWidth: '600px', margin: '0 auto', padding: '32px 40px' }
const h1 = { fontSize: '20px', fontWeight: '700' as const, color: '#1a1f3a', margin: '0 0 24px' }
const fieldSection = { marginBottom: '16px' }
const label = { margin: '0 0 4px', fontSize: '12px', fontWeight: '600' as const, color: '#9ca3af', textTransform: 'uppercase' as const, letterSpacing: '1px' }
const value = { margin: '0', fontSize: '15px', color: '#1a1f3a' }
const divider = { borderColor: '#eee', margin: '20px 0' }
const messageBox = { backgroundColor: '#f9fafb', padding: '16px', borderRadius: '8px' }
const messageText = { margin: '0', fontSize: '14px', color: '#4a4a4a', lineHeight: '1.7' }
